# Creating a New VIP on a fw-proto Transactor

This skill walks an agent through creating a new **Verification IP (VIP)** — the
*methodology layer* — on top of an existing `fw-proto-<proto>` transactor kit. Two
validated VIPs calibrate the patterns below:

- **`fwvip-wb`** — a *synchronous, memory-mapped bus* (Wishbone): request/response,
  width-parameterized, with a register model.
- **`fwvip-uart`** — an *asynchronous, streaming line protocol* (UART): independent one-way
  TX/RX streams, fixed carrier width, runtime-configurable framing, no register model.

They span the range each design axis covers. Describe **your** protocol on its own terms —
don't force it into a bus or a stream shape because an example has that shape.

## Where this fits — the two layers

| Layer | Package | Built by | Contains |
|-------|---------|----------|----------|
| **Transactor kit** | `fw-proto-<proto>` | the **`fw-proto-create`** skill | Signal-level, per-instance transactors (core ↔ pins, in-built FIFOs, blocking task API), a method-level API + per-role bridges, an optional runtime-config API, and a protocol checker. |
| **VIP / methodology** | `fwvip-<proto>` | **this skill** | A UVM agent set *and* a Python/cocotb front-end built **on top of** the kit. No RTL FSMs, no checker. |

`fwvip-core` supplies shared infrastructure: clock/reset transactors + UVM config providers
(`fwvip_clock_config` / `fwvip_reset_config`) for reset synchronization, and the canonical
cocotb ready/valid handshake (`docs/cocotb-performance.md`).

> **Hard prerequisite.** The transactor kit `fw-proto-<proto>` must already exist — the VIP
> *consumes* it, never rebuilds it. If the kit is missing, build it with **`fw-proto-create`**
> first. This skill never creates cores, interfaces, wrappers, bridges, or checkers.

### What the VIP consumes from the kit

For each role the kit exports (names: Wishbone `wb_*` / UART `uart_*`):

- **Transactor wrappers** `<proto>_<role>_xtor` — instantiate in the bench. Each holds a
  `u_if` instance with a **blocking task API** and/or a held-config `configure(...)`.
- **Transactor cores** `<proto>_<role>_xtor_core` with generic ready/valid ports
  (`req_*`/`rsp_*`, or role streams like `mon_*`) and discrete `cfg_*` ports for held config
  — the Python/cocotb backend drives these via instance handles.
- **Method API + per-role bridges** in the kit SV package `fw_proto_<proto>_pkg`: the
  interface-classes (`wb_proto_if`; `uart_tx_if`/`uart_rx_if`/`uart_monitor_if`) and the
  `<proto>_<role>_xtor_bridge` classes that connect the task API to the method API.
- **Runtime-config API** (if the protocol has one) `<proto>_config_if` — the kit's
  held-level `configure(...)`.
- **Protocol checker** module `<proto>_proto_checker` (consume it; don't vendor a copy).
- **DFM exports** — Wishbone `fw.proto.wb.{xtor-core,xtor-sv,class,checker}`; UART
  `fw.proto.uart.{files,xtor-core,checker}`.

## The two reference VIPs at a glance

The same skill produces both. Where they differ is **driven by the protocol**, not by taste:

| Axis | `fwvip-wb` (bus) | `fwvip-uart` (stream) |
|---|---|---|
| Roles → archetypes | initiator=*driving*, target=*responder*, monitor=*passive* | tx=*driving*, rx=*passive consumer*, monitor=*passive* |
| Carrier / widths | width-parameterized (`ADDR/DATA_WIDTH_MAX`); `*_config_p #(vif_t, AW, DW)` | fixed carrier (`MAX_DATA_BITS/STATUS_BITS/DIV_WIDTH`); `*_config_p #(vif_t)` |
| Wire response | yes (read data + err) → **responder model** | none (one-way) → **no responder** |
| Runtime config | none | framing object (`divisor/word/parity/stop`) → kit `uart_config_if` |
| Register model | `uvm_reg_adapter` | none (not memory-mapped) |
| Passive delivery | monitor **polls** `wait_txn()` | rx/monitor **push** via `recv()`/`observe()` callbacks |

---

## What you'll build (layout)

```
fwvip-<proto>/
  flow.yaml                              # dfm package org.fwvip.<proto>; imports fw-proto-<proto> + fwvip-core
  ivpm.yaml                              # deps: fw-proto-<proto>, fwvip-core, cocotb, …
  skills/fwvip-<proto>-usage/SKILL.md    # agent-facing "how to use this VIP" skill (Step 12)
  src/
    vip.yaml                            # FileSets: xtor-pkg + vip-uvm-hvlsrc
    uvm/
      fwvip_<proto>_xtor_pkg.sv         # consumer-side constants (widths / carrier sizes)
      fwvip_<proto>_pkg.sv              # the VIP package compilation unit
      fwvip_<proto>_macros.svh          # `fwvip_<proto>_<role>_register(...) helpers
      fwvip_<proto>_transaction.svh     # uvm_sequence_item
      fwvip_<proto>_<config>.svh        # (optional) runtime-config uvm_object
      fwvip_<proto>_<role>*.svh         # per role: agent, config(+_p seam adapter), [driver, seq, …]
      fwvip_<proto>_reg_adapter.svh     # (memory-mapped protocols only)
    python/org/fwvip/<proto>/           # backend-independent front-end + cocotb backend
      transaction.py backend.py <role>.py  cocotb/backend.py
  tests/  uvm/{tb,env,tests}/  cocotb/  formal/   # benches; formal consumes the kit checker
```

---

## Step 1 — Map the kit's roles onto archetypes

The kit defines the protocol's roles; classify each by **how data crosses the seam**, which
dictates its UVM shape:

- **Driving / active** (WB initiator, UART tx) — the VIP *calls* the transactor to push
  stimulus. An active agent (sequencer + 1:1 driver).
- **Responder** (WB target) — *request/response protocols only*. The transactor *calls back*
  into the VIP with each observed request; the VIP returns a response.
- **Passive consumer / observer** (WB monitor, UART rx, UART monitor) — an analysis-stream
  producer. The transactor delivers received/observed data; the VIP republishes it on a
  `uvm_analysis_port`.

A protocol with no wire response (UART) has **no responder role** and needs no register
model. A streaming protocol's "receive" side is a *passive consumer*, not a responder.

---

## Step 2 — Consumer-side constants package

The transactor cores are per-instance parameterized; the class-based UVM VIP is not, so it
fixes its own sizes in a tiny package compiled first. Two shapes:

```sv
// Width-parameterized bus (fwvip-wb): the kit vif is #(AW,DW), so the config_p threads them.
package fwvip_wb_xtor_pkg;
    parameter int ADDR_WIDTH_MAX = 64;
    parameter int DATA_WIDTH_MAX = 64;
endpackage

// Fixed-carrier stream (fwvip-uart): plain localparams; the config_p is #(vif_t) only.
package fwvip_uart_xtor_pkg;
    parameter int MAX_DATA_BITS = 8;   // carrier; runtime word_bits selects significant bits
    parameter int STATUS_BITS   = 4;   // line-error nibble {OE,BI,FE,PE}
    parameter int DIV_WIDTH     = 16;  // baud divisor
endpackage
```

Every VIP class sizes its fields with these constants.

---

## Step 3 — The transaction item

A `uvm_sequence_item` carrying one protocol transfer. Model exactly what the protocol moves:

- **Bus (WB):** `adr`, `dat`, `sel`, `we`, `err` (the driver updates `dat`/`err` in place on
  reads).
- **Stream (UART):** one `data` character + a `status` nibble + a tap tag (`is_tx`); no
  address, no byte-enable, no request/response pairing. Add decode helpers
  (`parity_err()`, …) and `convert2string()`.

---

## Step 4 — Runtime-configuration object *(only if the protocol has runtime-configurable attributes)*

Static/build-time attributes stay as kit module `parameter`s. *Runtime*-configurable
attributes get a `uvm_object` mirroring the kit's `<proto>_config_if`. UART's
`fwvip_uart_framing` carries `divisor/word_bits/parity_*/stop_bits`, offers presets
(`p8n1()`, `p7e1()`, …), and a `mask()` helper. A cfg (virtual) sequence applies it via each
role config's `configure(f)`, which forwards to the transactor's held-level `configure(...)`.
WB has none — skip this step.

---

## Step 5 — UVM package + the **seam-adapter config** pattern

```sv
// fwvip_<proto>_pkg.sv
`include "uvm_macros.svh"
`include "fwvip_<proto>_macros.svh"
package fwvip_<proto>_pkg;
    import uvm_pkg::*;
    import fwvip_<proto>_xtor_pkg::*;   // Step 2 constants
    import fw_proto_<proto>_pkg::*;     // kit class layer: interface-classes + *_xtor_bridge
    // Data/config first (they parameterize configs/sequences), then per role.
    `include "fwvip_<proto>_transaction.svh"
    // … (optional) framing/config object …
    // … per-role: config, [driver], [seq], agent …
    // … (optional) reg adapter …
endpackage
```

Compile order matters: a type used as a parameter (e.g. a responder item, or the
transaction) must be included before the component that specializes on it.

**The seam adapter (every role uses this).** Each role has an abstract config (the
vif-agnostic type stored in / fetched from the config DB) and a width/vif-aware
specialization `*_config_p #(type vif_t [, int AW, int DW])` that:

1. holds the kit transactor vif,
2. constructs a kit `<proto>_<role>_xtor_bridge` from it,
3. **implements or forwards** the kit's method API for that role, and
4. exposes a static `set()` placing itself into `uvm_config_db` under `"cfg"`.

This is what lets a non-parameterized component talk to a parameterized transactor, and it
is the single pattern shared by *all* roles in *both* VIPs.

---

## Step 6 — Wire each role by its interaction pattern

Pick the pattern per role (Step 1). All three appear across the two reference VIPs.

### Pattern A — Call-driven (driving role: WB initiator, UART tx)
Active agent: sequencer + a 1:1 driver whose `run_phase` pulls an item and calls the config,
which calls the kit. No background thread.

```sv
// driver run_phase
forever begin
    seq_item_port.get_next_item(t);
    m_cfg.send(t.data);            // UART: config.send -> bridge.send
    //  or: m_cfg.access(t);       // WB: config.access -> vif.request()/response(), capture read data
    seq_item_port.item_done();
end
```
WB's `access()` does `vif.request(adr,dat,sel,we); vif.response(dat_t,err);` and writes read
data back into `t`. UART's `send()` lazily builds the bridge (`ensure()`) then `bridge.send(data)`.

### Pattern B — Callback responder (request/response only: WB target)
The kit's `<proto>_target_xtor_bridge` polls the request FIFO and *calls* a method-API
callback per request; the VIP rides that callback into a UVM responder sequence:

- `*_config_p implements <proto>_proto_if #(AW,DW)`, owns the bridge, and `start()`s it.
  Its exact-width `access(...)` builds a MAX-width transaction and hands it to the driver via
  `m_drv.service(t)`, then copies `dat_r`/`err` back.
- the driver's `run_phase` is just `m_cfg.start(this); wait fork;`; its `service(t)` does
  `get_next_item(it); it.access(t); item_done();`.
- UVM forbids sending a sequence to `start_item()` (`SEQNOTITM`), so the responder sequence
  (`implements fwvip_<proto>_target_if`) sends a lightweight **wrapper item** carrying a
  handle back to itself; `it.access(t)` forwards to the responder's `handle_request(t)`.

Flow: **bus → kit bridge → config.access() → driver.service() → sequencer → handle_request()**.
The responder is *called*, never polls. (A reusable memory responder belongs in the test/env
library, not the VIP package.)

### Pattern C — Passive analysis producer (WB monitor, UART rx, UART monitor)
The agent owns a `uvm_analysis_port`, hands it to the config (`set_ap(ap)`), and the config
republishes each item. Two delivery sub-flavors — use whichever the kit offers:

- **C1 push-callback (UART rx/monitor).** `*_config_p implements <proto>_<role>_if`; its
  agent's `run_phase` calls `m_cfg.start()`, which builds the kit consumer bridge with `this`
  as the sink and forks `run()` — the bridge then *calls* `recv(...)` / `observe(...)` per
  item, and the config does `ap.write(t)`. (RX's `recv()` can block on a `set_stall` knob to
  provoke overrun — a deliberate backpressure hook.)
- **C2 poll-loop (WB monitor).** The agent's `run_phase` loops `m_cfg.wait_txn(...)` (which
  delegates to `vif.wait_txn(...)`), builds a transaction, and `ap.write(t)`.

---

## Step 7 — Register adapter *(memory-mapped protocols only)*

If the protocol is memory-mapped, supply a `uvm_reg_adapter` mapping `uvm_reg_bus_op` ↔ the
VIP transaction (`reg2bus`/`bus2reg`) so a `uvm_reg_block` can run front-door over the VIP.
Streaming protocols (UART) have no addresses and skip this.

---

## Step 8 — Register macros

Provide one-line config-DB binding macros, each expanding to the matching
`*_config_p #(...)::set(...)`. The threaded arguments are protocol-shaped:

```sv
// Bus (widths threaded):
`define fwvip_wb_initiator_register(ADDR_WIDTH,DATA_WIDTH,vif,inst) \
    fwvip_wb_initiator_config_p #(virtual wb_initiator_xtor_if #(ADDR_WIDTH,DATA_WIDTH), \
        ADDR_WIDTH, DATA_WIDTH)::set(null, "", "cfg", vif);

// Stream (no widths; monitor adds a tap selector):
`define fwvip_uart_tx_register(vif, inst) \
    fwvip_uart_tx_config_p #(virtual uart_tx_xtor_if)::set(null, inst, "cfg", vif);
`define fwvip_uart_monitor_register(vif, inst, is_tx) \
    fwvip_uart_monitor_config_p #(virtual uart_monitor_xtor_if)::set(null, inst, "cfg", vif, is_tx);
```

---

## Step 9 — Python / cocotb front-end

The VIP also ships a **backend-independent Python front-end** so the same VIP drives a cocotb
(or pure-Python, or DPI) environment. Three thin layers:

1. **`transaction.py`** — dataclasses + a `*Layout` that packs/unpacks the ready/valid bit
   vectors (MSB-first, matching the kit's packed structs). A held *runtime config* is **not**
   a streamed vector — carry it as a plain dataclass (UART `UartFraming`) the backend drives
   onto the core's discrete `cfg_*` ports.
2. **`backend.py`** — abstract base classes that only move bits + expose reset (and
   `configure()` if there's held config). Shape follows the streams: a paired bus exposes
   `push_request`/`pop_response` (WB); independent one-way streams expose role-specific
   `push_char` / `pop_char` / `pop` (UART).
3. **`<role>.py`** — friendly front-ends over a backend (WB `write/read`,
   `serve_memory`, `next`; UART `send`, `recv`, `next` + async iteration; `configure(framing)`).

The **cocotb backend** (`cocotb/backend.py`) is constructed from a handle to a transactor
*core* (`dut.u_<role>`), drives its RV ports with the canonical event-driven primitives
(`_rv_get`/`_rv_put`: sleep on the signal edge while idle; transfer + settle on clock edges),
and writes held config straight to the `cfg_*` ports. See
`fwvip-core/docs/cocotb-performance.md`.

---

## Step 10 — Bench wiring + reset synchronization

A thin **hdl_top** / **hvl_top** split:

- **hdl_top** instantiates the kit transactor wrappers (`<proto>_<role>_xtor`) on a shared
  bus/line, plus the **fwvip-core** clock/reset transactor interfaces. Bind the kit checker
  here if the bench checks the protocol. Add any protocol-specific injection interface (UART
  has a raw-line `inject_if` for FE/BI scenarios).
- **hvl_top** binds: call the `fwvip_<proto>_<role>_register(...)` macros pointing at
  `u_hdl.u_<role>.u_if`, set the `fwvip_clock_config_p`/`fwvip_reset_config_p` providers (and
  any extra vifs) into the config DB, then `run_test()`.

> **Reset is sourced from fwvip-core, not faked.** The env retrieves the reset/clock
> providers and the base virtual sequence waits on the reset provider before driving
> stimulus. Do **not** reintroduce fixed-delay `wait_reset` hacks.

The **env** builds the agents + a virtual sequencer + a scoreboard, wires the vseqr to the
sub-sequencers/configs, and connects analysis ports to the scoreboard. Scoreboard topology is
protocol-shaped: WB feeds the single monitor stream in; UART uses the **TX-line monitor tap as
the reference** and the **RX stream as delivered**. The reusable sequence library lives in the
test/env package, not the VIP.

---

## Step 11 — DFM packaging & tests

**Package `flow.yaml`** imports the kit and fwvip-core and pulls in the fragments:

```yaml
package:
  name: org.fwvip.<proto>
  imports:
  - "${{ rootdir }}/../fw-proto-<proto>/flow.yaml"   # transactor kit
  - "${{ rootdir }}/../fwvip-core/flow.yaml"          # clock/reset providers
  fragments: [src/vip.yaml, tests/flow.yaml]
```

**`src/vip.yaml`** exports the constants package first, then the UVM package (which `needs`
the kit's class layer): WB needs `fw.proto.wb.xtor-sv` + `fw.proto.wb.class`; UART needs
`fw.proto.uart.files`. Include only the package compilation unit (`fwvip_<proto>_pkg.sv`); the
`.svh` classes come in via the incdir (globbing `*.sv` double-compiles the xtor-pkg).

**Tests.** UVM scenarios run one image + one test class selected by a `+SEQ=<vseq>` plusarg.
The cocotb flow uses the `dv-flow-libcocotb` tasks and needs the kit's `xtor-core`. The formal
TBs consume the kit's `<proto>_proto_checker` directly — the VIP vendors no checker.

```sh
dfm run org.fwvip.<proto>.uvm-test-smoke    # UVM smoke
dfm run org.fwvip.<proto>.cocotb-check      # cocotb front-end over the cores
```

---

## Step 12 — VIP Usage Skill (required)

Creating the VIP is only half the job. It exists so *another* agent can drop it into a
testbench — and that agent needs instructions written for **this specific VIP**, not the
generic patterns above. So every VIP ships its own **`fwvip-<proto>-usage` skill**: a SKILL.md, authored
as the final step, that teaches an agent how to connect and drive *this* VIP.

Do **not** skip it, and do **not** make it generic. Fill it with the concrete role set, class
names, register macros, task/sequence signatures, runtime-config object, and Python front-end
calls this VIP actually exposes — copied from the files you just generated and verified.

### Location and frontmatter

`skills/fwvip-<proto>-usage/SKILL.md` (named after the VIP, e.g. `fwvip-wb-usage`, to stay unique):

```markdown
---
name: fwvip-<proto>-usage
description: Connect and drive the fwvip-<proto> Verification IP — bind its agents into a
  UVM env (register macros + config DB), write stimulus/responder sequences, apply runtime
  config, [run the reg-model front door,] and/or drive the cocotb front-end. Use when
  integrating fwvip-<proto> into a testbench or generating stimulus for it.
tools: Read, Write, Edit, Bash, Grep, Glob
---
```

The `description` must name the protocol and the verbs an integrator searches for
("connect", "drive", "stimulus", "configure", "reg model" if applicable).

### Required content (concrete for this VIP)

1. **What the VIP provides** — its actual agents (e.g. initiator/target/monitor, or
   tx/rx/monitor), the transaction, any runtime-config object, the reg adapter *if present*,
   and the Python front-end. One line each — describe the real role set, not a fixed triad.
2. **DFM dependency** — package `org.fwvip.<proto>`, the FileSet to `need`
   (`org.fwvip.<proto>.vip-uvm-hvlsrc`), and that it transitively pulls the kit. Copy real
   names from `src/vip.yaml`.
3. **UVM bench wiring** — hdl_top (kit `<proto>_<role>_xtor` + fwvip-core clock/reset ifs +
   any injection if) and hvl_top (the `register(...)` macro calls + providers + `run_test()`),
   as a copy-pasteable skeleton with real argument lists.
4. **Stimulus & responders/consumers** — how to drive the active role(s); for a
   request/response protocol, how to write a responder by extending the responder sequence and
   overriding `handle_request`; for a passive consumer, how to subscribe to its analysis port.
5. **Runtime configuration** — *if present*, how to build/apply the config object (e.g. the
   framing presets) to each role.
6. **Register model** — *if present*, how to attach the reg adapter to a `uvm_reg_block`/map.
7. **cocotb front-end** — constructing the `*` front-ends from `Cocotb*Backend(dut.u_<role>)`
   and the real calls, with the plain-Verilog top showing the cores wired up.
8. **Pitfalls** — reset from the fwvip-core providers (no fixed-delay hacks); **no
   `typedef virtual <if>#(…)` in procedural code** (Verilator crash) — use the register macros;
   width/carrier policy; cocotb backends bind to the transactor *core* handle.
9. **A minimal worked example** — point at `tests/uvm/` and `tests/cocotb/` with the
   `dfm run` commands.

### Source of truth

Generate the usage skill **from the files you just created**, after they pass their tests —
so names, macros, and signatures match real, working code. Update it in the same change as the
VIP.

---

## Pitfalls (carry into the VIP and its usage skill)

- **Don't rebuild the kit.** Cores, interfaces, wrappers, bridges, method API, and checker
  belong to `fw-proto-<proto>`. The VIP only adds methodology classes and a Python front-end.
- **Let the protocol pick the role shapes.** Driving / responder / passive-consumer — not a
  hardcoded initiator/target/monitor triad. No wire response ⇒ no responder, no reg model.
- **Constants policy.** Width-parameterized bus ⇒ `*_WIDTH_MAX` + `*_config_p #(vif_t,AW,DW)`;
  fixed carrier ⇒ plain localparams + `*_config_p #(vif_t)`.
- **The seam adapter is the config.** Every role's `*_config_p` holds the vif, owns a kit
  bridge, and forwards/implements the kit method API. That is its whole reason to exist.
- **Passive ≠ responder.** A consumer republishes on an analysis port (push-callback or
  poll-loop); only a true request/response role uses the callback-responder + wrapper-item.
- **No `typedef virtual <if> #(…)` in procedural code** — Verilator crashes. Bind vifs via the
  `register` macros and access through the config.
- **Reset from fwvip-core.** Use the clock/reset providers, not fixed delays.
- **cocotb is event-driven.** Use the `_rv_get`/`_rv_put` handshake; drive held config onto
  the `cfg_*` ports. Don't clock-poll. See `fwvip-core/docs/cocotb-performance.md`.

---

## Reference VIPs

### `fwvip-wb` — synchronous memory-mapped bus

| File | Purpose |
|------|---------|
| `src/uvm/fwvip_wb_xtor_pkg.sv` | `ADDR/DATA_WIDTH_MAX` (width-parameterized policy) |
| `src/uvm/fwvip_wb_pkg.sv` | VIP package (imports `fw_proto_wb_pkg`) |
| `src/uvm/fwvip_wb_transaction.svh` | adr/dat/sel/we/err item |
| `src/uvm/fwvip_wb_initiator*.svh` | Pattern A: driver calls `vif.request/response` |
| `src/uvm/fwvip_wb_target*.svh` | Pattern B: responder via kit bridge (config_p+if+item+driver) |
| `src/uvm/fwvip_wb_monitor*.svh` | Pattern C2: poll `vif.wait_txn` |
| `src/uvm/fwvip_wb_reg_adapter.svh` | `uvm_reg_adapter` |
| `src/uvm/fwvip_wb_macros.svh` | width-threaded `register` macros |
| `src/python/org/fwvip/wb/` | front-end + cocotb backend |

### `fwvip-uart` — asynchronous streaming line protocol

| File | Purpose |
|------|---------|
| `src/uvm/fwvip_uart_xtor_pkg.sv` | `MAX_DATA_BITS/STATUS_BITS/DIV_WIDTH` (fixed-carrier policy) |
| `src/uvm/fwvip_uart_pkg.sv` | VIP package (imports `fw_proto_uart_pkg`) |
| `src/uvm/fwvip_uart_transaction.svh` | character + status nibble + tap tag |
| `src/uvm/fwvip_uart_framing.svh` | runtime-config object + presets (Step 4) |
| `src/uvm/fwvip_uart_tx*.svh` | Pattern A: driver calls `config.send` |
| `src/uvm/fwvip_uart_rx*.svh` | Pattern C1: push `recv()` callback → analysis port (+ stall knob) |
| `src/uvm/fwvip_uart_monitor*.svh` | Pattern C1: push `observe()` callback → analysis port |
| `src/uvm/fwvip_uart_macros.svh` | no-width `register` macros (+ monitor tap selector) |
| `src/python/org/fwvip/uart/` | front-end + cocotb backend (held framing on `cfg_*`) |

### Running

```sh
dfm run org.fwvip.wb.uvm-test-smoke      # WB: writes + self-checked readback
dfm run org.fwvip.wb.uvm-test-reg        # WB: reg-model front door
dfm run org.fwvip.wb.cocotb-check        # WB: cocotb front-end
dfm run org.fwvip.uart.uvm-test-smoke    # UART: TX→RX, scoreboard-checked
dfm run org.fwvip.uart.cocotb-check      # UART: cocotb front-end
```

Use `dfm show tasks --root tests/` to list all scenario tasks.
