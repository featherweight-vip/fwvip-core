# Creating a New VIP with fwvip-common

This skill walks an agent through creating a new Verification IP (VIP) using the `fwvip-common` framework. The canonical reference is the Wishbone B.3 example at `resources/example/wishbone/`.

## Overview

A fwvip-common VIP contains:
- Three transactor cores (initiator, target, monitor) — pure RTL, signal-level only
- Three SV interfaces (one per transactor) — wrap `fwvip_sv_ingress_fifo` / `fwvip_sv_egress_fifo`
- Three SV wrapper modules — bind core to interface
- A protocol checker (`fwvip_*_checker.sv`) — synthesizable assertions for use in simulation and formal
- Transaction struct macros in a `.svh` header
- Tests: core-only simulation, SV-wrapper simulation, formal BMC
- `flow.yaml` files at each directory level for DFM

---

## Step 1 — Architecture Plan

Before writing any code, analyze the protocol:

1. **Identify configurable parameters**: signal widths, number of lanes, etc. These become `parameter` declarations on the core modules.

2. **Identify independent activity streams**: e.g., a memory protocol has a request stream and a response stream. A serial protocol abstracts at the word level, not bit level. Each stream will have its own FIFO and its own FSM.

3. **Determine FIFO directions per transactor**:
   - Initiator: request stream → **ingress FIFO** (testbench pushes in), response stream → **egress FIFO** (testbench reads out)
   - Target: mirrors the initiator — request stream → **egress FIFO**, response stream → **ingress FIFO**
   - Monitor: all streams → **egress FIFOs** (passive observer only)

4. **Design transaction structs** for each stream. Use a `packed struct` and a width macro. See `fwvip_wb_macros.svh`:
   ```sv
   `define FWVIP_WB_REQ_STRUCT(ADDR_WIDTH, DATA_WIDTH) \
       struct packed { \
           bit[ADDR_WIDTH-1:0] adr; \
           bit[DATA_WIDTH-1:0] dat; \
           bit                 we;  \
       }
   `define FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH) ((ADDR_WIDTH) + (DATA_WIDTH) + 1)
   ```
   The width macro must be computable from parameters without `$bits()` — Yosys/sby cannot evaluate `$bits()` on anonymous structs in parameter defaults.

5. **Design one FSM per stream per transactor**. FSMs must be fully independent — no shared state between streams. Benefits: simpler machines, better throughput, natural FIFO buffering.

6. **Identify protocol invariants** (e.g., "CYC must be high while STB is asserted"). These become checker assertions.

---

## Step 2 — Directory Layout

Create the following structure (replace `<proto>` with your protocol abbreviation, e.g., `wb` → prefix `fwvip_wb_`):

```
resources/example/<proto>/
  flow.yaml                              # package-level DFM config
  src/
    sv/
      flow.yaml                          # fragment: exports for each core/interface/wrapper
      fwvip_<proto>_macros.svh           # transaction struct + width macros
      fwvip_<proto>_initiator_core.sv    # pure-RTL initiator core
      fwvip_<proto>_target_core.sv       # pure-RTL target core
      fwvip_<proto>_monitor_core.sv      # pure-RTL monitor core
      fwvip_<proto>_initiator_if.sv      # SV interface — delegates to FIFO instances
      fwvip_<proto>_target_if.sv
      fwvip_<proto>_monitor_if.sv
      fwvip_<proto>_initiator_sv.sv      # thin wrapper: core + interface
      fwvip_<proto>_target_sv.sv
      fwvip_<proto>_monitor_sv.sv
      fwvip_<proto>_checker.sv           # synthesizable assertions
  tests/
    flow.yaml                            # test package DFM config (imports VIP package)
    sim/
      flow.yaml                          # simulation tasks
      b2b_tb.sv                          # core-only back-to-back testbench
      b2b_sv_tb.sv                       # SV-wrapper back-to-back testbench
    formal/
      flow.yaml                          # formal tasks
      fwvip_<proto>_formal_b2b_tb.sv     # formal back-to-back testbench
```

---

## Step 3 — Core Transactor (`*_core.sv`)

Rules:
- Module ports only — no `interface`, no `` `include `` of interface files
- Parameters for all configurable widths
- Derived width parameters using macros (not `$bits()`)
- One `always @(posedge clock or posedge reset)` block per independent stream FSM
- FIFO handshake: `req_valid`/`req_data`/`req_ready` (ingress), `rsp_valid`/`rsp_data`/`rsp_ready` (egress)

Wishbone initiator core port pattern:
```sv
module fwvip_wb_initiator_core #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int _REQ_WIDTH = `FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH),
    parameter int _RSP_WIDTH = `FWVIP_WB_RSP_WIDTH(ADDR_WIDTH, DATA_WIDTH)
) (
    input                       clock, reset,
    // Protocol signals
    output reg [ADDR_WIDTH-1:0] adr,
    output reg                  cyc, stb, we,
    input                       ack, err,
    output reg [(DATA_WIDTH/8)-1:0] sel,
    output reg [DATA_WIDTH-1:0] dat_w,
    input      [DATA_WIDTH-1:0] dat_r,
    // FIFO ports
    input                       req_valid,
    input      [_REQ_WIDTH-1:0] req_data,
    output reg                  req_ready,
    output reg                  rsp_valid,
    output reg [_REQ_WIDTH-1:0] rsp_data,
    input                       rsp_ready
);
```

FSM pattern — independent request and response state machines:
```sv
// Request FSM
always @(posedge clock or posedge reset) begin
    if (reset) begin /* reset all regs */ end
    else case (req_state)
        ST_IDLE: if (req_valid) begin /* latch request, assert CYC/STB, advance state */ end
        ST_WAIT: if (ack || err) begin /* handle ACK, loop or return to IDLE */ end
    endcase
end

// Response FSM (or inline response logic in the same always block as above)
// Latch response data on ACK, hold rsp_valid until rsp_ready consumed
```

---

## Step 4 — SV Interface (`*_if.sv`)

Rules:
- `interface … (input clock, input reset)`
- Use `always @(posedge clock …)` — **never `always_ff`** (Verilator crash)
- Do **not** use `automatic logic` inside `always` blocks — use interface-level `reg`
- Instantiate `fwvip_sv_ingress_fifo` for each ingress stream, `fwvip_sv_egress_fifo` for each egress stream
- Expose `task put(…)` and `task get(…)` that delegate to the FIFO instances

Wishbone initiator interface pattern:
```sv
`include "fwvip_wb_macros.svh"

interface fwvip_wb_initiator_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int _REQ_WIDTH = `FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH)
) (input clock, input reset);

    wire req_valid, req_ready;
    wire [_REQ_WIDTH-1:0] req_data;
    wire rsp_valid, rsp_ready;
    wire [_REQ_WIDTH-1:0] rsp_data;

    fwvip_sv_ingress_fifo #(.WIDTH(_REQ_WIDTH)) req_fifo (
        .clock(clock), .reset(reset),
        .valid(req_valid), .data(req_data), .ready(req_ready)
    );
    fwvip_sv_egress_fifo #(.WIDTH(_REQ_WIDTH)) rsp_fifo (
        .clock(clock), .reset(reset),
        .valid(rsp_valid), .data(rsp_data), .ready(rsp_ready)
    );

    task req_put(bit [_REQ_WIDTH-1:0] data); req_fifo.put(data); endtask
    task rsp_get(output bit [_REQ_WIDTH-1:0] data); rsp_fifo.get(data); endtask
endinterface
```

---

## Step 5 — SV Wrapper Module (`*_sv.sv`)

The wrapper instantiates both the core and the interface, wiring FIFO signals between them:

```sv
module fwvip_wb_initiator_sv #(/* same params as core */) (
    input clock, reset,
    // Protocol bus ports only — no FIFO ports
    output [ADDR_WIDTH-1:0] adr, …
);
    fwvip_wb_initiator_if #(.ADDR_WIDTH(ADDR_WIDTH), …) bfm_if (.clock(clock), .reset(reset));

    fwvip_wb_initiator_core #(.ADDR_WIDTH(ADDR_WIDTH), …) core (
        .clock(clock), .reset(reset),
        // Protocol signals connect to module ports
        .adr(adr), .cyc(cyc), …,
        // FIFO signals connect to bfm_if wires
        .req_valid(bfm_if.req_valid), .req_data(bfm_if.req_data), .req_ready(bfm_if.req_ready),
        .rsp_valid(bfm_if.rsp_valid), .rsp_data(bfm_if.rsp_data), .rsp_ready(bfm_if.rsp_ready)
    );
endmodule
```

The testbench accesses the interface via direct hierarchical reference:
```sv
// In the testbench — no typedef virtual needed
u_initiator.bfm_if.req_put({addr, data, 1'b1});
u_initiator.bfm_if.rsp_get(rsp);
```

---

## Step 6 — Protocol Checker (`fwvip_*_checker.sv`)

Write synthesizable assertions (compatible with Yosys/sby for formal verification):

```sv
module fwvip_wb_checker #(parameter int ADDR_WIDTH=32, parameter int DATA_WIDTH=32) (
    input clock, reset, cyc, stb, ack, err, we, …
);
    // Example: STB requires CYC
    always @(posedge clock) begin
        if (!reset && stb) assert(cyc) else $error("STB without CYC");
    end
endmodule
```

---

## Step 7 — Tests

### Core-only testbench (`b2b_tb.sv`)
Instantiate initiator core and target core back-to-back. Drive requests into the initiator's ingress FIFO directly (using `initial` blocks and `@(posedge clock)`). Verify responses. Include the checker.

### SV-wrapper testbench (`b2b_sv_tb.sv`)
Instantiate `fwvip_*_initiator_sv`, `fwvip_*_target_sv`, `fwvip_*_monitor_sv`. Connect bus wires between them. Call tasks via hierarchical reference:
```sv
u_initiator.bfm_if.req_put({addr, data, 1'b0});
u_initiator.bfm_if.rsp_get(rsp);
u_monitor.bfm_if.get(mon_data);
```

**Do not use `typedef virtual` for parameterized interfaces with Verilator** — it crashes. Use direct hierarchical paths instead.

### Formal testbench (`fwvip_*_formal_b2b_tb.sv`)
Instantiate initiator core + target core + checker. Use `assume` on FIFO inputs, `assert` on properties. Compatible with Yosys/sby BMC.

---

## Step 8 — flow.yaml Files

### VIP package `flow.yaml` (at `resources/example/<proto>/flow.yaml`)
```yaml
package:
  name: org.featherweight-vip.<proto>
  imports:
  - ${{ srcdir }}/../../../flow.yaml  # import fwvip-common
  fragments:
  - src/sv/flow.yaml
```

### SV sources fragment (`src/sv/flow.yaml`)
```yaml
fragment:
  name: src
  tasks:
  - export: initiator-core
    uses: std.FileSet
    with: {type: systemVerilogSource, include: [fwvip_<proto>_initiator_core.sv], incdirs: [${{ srcdir }}]}

  - export: initiator-sv
    uses: std.FileSet
    needs:
    - org.fwvip.common.ingress-fifo
    - org.fwvip.common.egress-fifo
    with: {type: systemVerilogSource, include: [fwvip_<proto>_initiator_if.sv, fwvip_<proto>_initiator_sv.sv], incdirs: [${{ srcdir }}]}

  # Similarly for target-core, target-sv, monitor-core, monitor-sv, checker
  # monitor-sv only needs org.fwvip.common.egress-fifo
```

The `needs:` on an `export:` task causes the FIFO files to be included automatically whenever a downstream task depends on `initiator-sv`.

### Test package `flow.yaml` (`tests/flow.yaml`)
```yaml
package:
  name: org.featherweight-vip.<proto>.tests
  imports:
  - ${{ rootdir }}/../flow.yaml  # import the VIP package
  fragments:
  - sim/flow.yaml
  - formal/flow.yaml
```

### Simulation fragment (`tests/sim/flow.yaml`)
```yaml
fragment:
  name: sim
  tasks:
  - local: b2b
    uses: hdlsim.vlt.SimImage
    with: {top: [b2b_tb]}
    needs:
    - org.featherweight-vip.<proto>.src.initiator-core
    - org.featherweight-vip.<proto>.src.target-core
    - org.featherweight-vip.<proto>.src.checker
    - b2b-src

  - root: b2b-sim
    uses: hdlsim.vlt.SimRun
    needs: [b2b]

  - local: b2b-src
    uses: std.FileSet
    with: {type: systemVerilogSource, include: [b2b_tb.sv]}
```

**Fragment name uniqueness**: Fragment names must be globally unique across all loaded packages. If running tests in a workspace that also loads `fwvip-common` tests, ensure fragment names do not collide (e.g., fwvip-common uses `fifo-sim`, not `sim`).

### Formal fragment (`tests/formal/flow.yaml`)
```yaml
fragment:
  name: formal
  tasks:
  - local: sby-path
    uses: std.SetEnv
    with:
      prepend_path: {PATH: /tools/symbiyosys/<version>/bin}

  - root: <proto>-b2b-bmc
    uses: formal.sby.BMC
    with: {top: fwvip_<proto>_formal_b2b_tb, depth: 20}
    needs:
    - org.featherweight-vip.<proto>.src.initiator-core
    - org.featherweight-vip.<proto>.src.target-core
    - org.featherweight-vip.<proto>.src.checker
    - formal-src
    - sby-path

  - local: formal-src
    uses: std.FileSet
    with: {type: systemVerilogSource, include: [fwvip_<proto>_formal_b2b_tb.sv]}
```

---

## Wishbone Example Reference

The complete working example is at `resources/example/wishbone/`. Key files:

| File | Purpose |
|------|---------|
| `src/sv/fwvip_wb_macros.svh` | Request/response packed struct macros and arithmetic width macros |
| `src/sv/fwvip_wb_initiator_core.sv` | Initiator RTL: req FSM drives CYC/STB/ADR/DAT_W, captures ACK into rsp egress FIFO |
| `src/sv/fwvip_wb_target_core.sv` | Target RTL: monitors CYC/STB into req egress FIFO, accepts rsp from ingress FIFO, asserts ACK |
| `src/sv/fwvip_wb_monitor_core.sv` | Monitor RTL: captures all bus activity passively into egress FIFOs |
| `src/sv/fwvip_wb_initiator_if.sv` | SV interface: `req_fifo` (ingress) + `rsp_fifo` (egress), `req_put()`/`rsp_get()` tasks |
| `src/sv/fwvip_wb_initiator_sv.sv` | Wrapper: exposes Wishbone B.3 ports, contains `bfm_if` + `core` instances |
| `src/sv/fwvip_wb_checker.sv` | Synthesizable assertions (CYC/STB protocol rules) |
| `tests/sim/b2b_tb.sv` | Core-only back-to-back sim test |
| `tests/sim/b2b_sv_tb.sv` | SV-wrapper back-to-back sim test with hierarchical interface calls |
| `tests/formal/fwvip_wb_formal_b2b_tb.sv` | Formal BMC testbench using sby |

### Wishbone transaction structs

```sv
`FWVIP_WB_REQ_STRUCT(32, 32)   // { bit[31:0] adr; bit[31:0] dat; bit we; }
`FWVIP_WB_RSP_STRUCT(32, 32)   // { bit[31:0] dat; bit err; }
`FWVIP_WB_MON_STRUCT(32, 32)   // { adr, dat, err, we, cyc_len }
```

### Running the tests

```sh
# From fwvip-common root
cd /path/to/fwvip-common

# Core-only simulation
packages/python/bin/python -m dv_flow.mgr run \
    org.featherweight-vip.wishbone.tests.sim.b2b-sim \
    --root resources/example/wishbone/tests/

# SV-wrapper simulation
packages/python/bin/python -m dv_flow.mgr run \
    org.featherweight-vip.wishbone.tests.sim.b2b-sv-sim \
    --root resources/example/wishbone/tests/

# Formal BMC proof
packages/python/bin/python -m dv_flow.mgr run \
    org.featherweight-vip.wishbone.tests.formal.wb-b2b-bmc \
    --root resources/example/wishbone/tests/
```

Task names follow the pattern: `<package-name>.<fragment-name>.<task-name>`. Use `dfm show tasks --root <tests-dir>` to list all available tasks.
