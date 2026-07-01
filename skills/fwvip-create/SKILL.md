---
name: fwvip-create
description: Create a new fwvip-<proto> Verification IP (the methodology layer) on top of an
  existing fw-proto-<proto> transactor kit — a UVM agent set (per-role agents, configs,
  drivers, sequences, optional register adapter + runtime-config object) and a Python/cocotb
  front-end, with simulation tests and a per-VIP usage skill. Use when asked to build,
  scaffold, or stand up a Featherweight VIP / UVM+cocotb agent set for a protocol whose
  transactor kit (fw-proto-<proto>) already exists.
tools: Read, Write, Edit, Bash, Grep, Glob
---

# fwvip-create — build a `fwvip-<proto>` VIP on a transactor kit

This skill builds the **methodology layer** (UVM agents + Python/cocotb front-end) on top of
an existing `fw-proto-<proto>` transactor kit. It is **self-contained**: the patterns below
are shown as concrete, copy-and-adapt code, calibrated on two validated VIPs —

- **`fwvip-wb`** — a synchronous, memory-mapped **bus** (request/response, width-parameterized,
  register model).
- **`fwvip-uart`** — an asynchronous, streaming **line protocol** (one-way TX/RX, fixed
  carrier, runtime framing, no register model).

They span the design axes. **Describe your protocol on its own terms** — the examples show the
*range* of choices, not a template to force-fit.

## The two layers (and the hard prerequisite)

| Layer | Package | Built by |
|---|---|---|
| Transactor kit (cores, SV interfaces, bridges, method API, checker) | `fw-proto-<proto>` | the **`fw-proto-create`** skill |
| **VIP / methodology (this skill)** | `fwvip-<proto>` | here |
| Shared infra (clock/reset providers, cocotb handshake) | `fwvip-core` | — |

> The kit **must already exist**. The VIP *consumes* it; it never creates cores, interfaces,
> wrappers, bridges, or checkers. If the kit is missing, build it with `fw-proto-create` first.

The VIP consumes, per role (Wishbone `wb_*` / UART `uart_*`):
- wrappers `<proto>_<role>_xtor` (each holds `u_if` with a blocking task API and/or held
  `configure(...)`),
- cores `<proto>_<role>_xtor_core` (generic ready/valid ports + discrete `cfg_*` ports),
- the kit SV package `fw_proto_<proto>_pkg` (interface-classes + `<proto>_<role>_xtor_bridge`),
- the checker `<proto>_proto_checker`,
- DFM exports (`fw.proto.wb.{xtor-core,xtor-sv,class,checker}`; `fw.proto.uart.{files,xtor-core,checker}`).

---

## Phase 1 — Classify the roles  *(do this first)*

The kit defines the protocol's roles. Classify each by **how data crosses the seam** — this
fixes its UVM shape and which of the three wiring patterns (Phase 6) it uses:

| Archetype | Examples | UVM shape | Pattern |
|---|---|---|---|
| **Driving / active** | WB initiator, UART tx | active agent: sequencer + 1:1 driver; VIP *calls* the transactor | **A** |
| **Responder** *(request/response only)* | WB target | transactor *calls back* a responder sequence | **B** |
| **Passive consumer / observer** | WB monitor, UART rx, UART monitor | analysis-stream producer | **C** |

Consequences: a protocol with **no wire response** (UART) has **no responder** and **no
register model**. A streaming "receive" side is a *passive consumer*, not a responder.

---

## Phase 2 — Consumer-side constants package

Compiled before everything else. Two shapes:

```sv
// Width-parameterized bus (fwvip_wb_xtor_pkg.sv): the kit vif is #(AW,DW),
// so the config_p will thread AW/DW too.
package fwvip_wb_xtor_pkg;
    parameter int ADDR_WIDTH_MAX = 64;
    parameter int DATA_WIDTH_MAX = 64;
endpackage

// Fixed-carrier stream (fwvip_uart_xtor_pkg.sv): plain localparams; config_p is #(vif_t).
package fwvip_uart_xtor_pkg;
    parameter int MAX_DATA_BITS = 8;   // carrier; runtime word_bits selects significant bits
    parameter int STATUS_BITS   = 4;   // line-error nibble {OE,BI,FE,PE}
    parameter int DIV_WIDTH     = 16;  // baud divisor
endpackage
```

---

## Phase 3 — The transaction item

Model exactly what the protocol moves.

```sv
// Bus: address/data/byte-enable/direction; driver updates dat/err in place on reads.
class fwvip_wb_transaction extends uvm_sequence_item;
    `uvm_object_utils(fwvip_wb_transaction)
    rand bit[ADDR_WIDTH_MAX-1:0]     adr;
    rand bit[DATA_WIDTH_MAX-1:0]     dat;
    rand bit[(DATA_WIDTH_MAX/8)-1:0] sel;
    rand bit                         we;
    bit                              err;
    function new(string name="fwvip_wb_transaction"); super.new(name); endfunction
endclass
```

```sv
// Stream: one character + status nibble + tap tag. No address, no req/rsp pairing.
class fwvip_uart_transaction extends uvm_sequence_item;
    `uvm_object_utils(fwvip_uart_transaction)
    rand bit [MAX_DATA_BITS-1:0] data;
    bit      [STATUS_BITS-1:0]   status;   // {OE,BI,FE,PE}; set on rx/monitor only
    bit                          is_tx;     // monitor tap direction (1=TX line)
    function new(string name="fwvip_uart_transaction"); super.new(name); endfunction
    function bit parity_err();  return status[0]; endfunction
    function bit framing_err(); return status[1]; endfunction
    function bit brk();         return status[2]; endfunction
    function bit overrun();     return status[3]; endfunction
endclass
```

---

## Phase 4 — Runtime-configuration object  *(only if the protocol has runtime-config attributes)*

Build-time attributes stay as kit module `parameter`s. *Runtime*-configurable attributes get a
`uvm_object` mirroring the kit's `<proto>_config_if`. WB has none → skip. UART:

```sv
class fwvip_uart_framing extends uvm_object;
    `uvm_object_utils(fwvip_uart_framing)
    bit [DIV_WIDTH-1:0] divisor      = DIV_WIDTH'(16);
    bit [3:0]           word_bits    = 4'd8;
    bit                 parity_en    = 1'b0;
    bit                 parity_even  = 1'b0;
    bit                 parity_stick = 1'b0;
    bit [1:0]           stop_bits    = 2'd0;   // 0=>1 stop; 1=>1.5/2
    function new(string name="fwvip_uart_framing"); super.new(name); endfunction

    static function fwvip_uart_framing p8n1(bit [DIV_WIDTH-1:0] div = 16);
        fwvip_uart_framing f = new();
        f.divisor=div; f.word_bits=4'd8; // (parity off, 1 stop by default)
        return f;
    endfunction
    // …p7e1(), p8o1(), p5n2(), p8stick()…
endclass
```

A cfg (virtual) sequence applies it through each role config's `configure(f)` (Phase 6), which
forwards to the transactor's held-level `configure(...)`.

---

## Phase 5 — Package skeleton + the seam-adapter config

```sv
// fwvip_<proto>_pkg.sv
`include "uvm_macros.svh"
`include "fwvip_<proto>_macros.svh"
package fwvip_<proto>_pkg;
    import uvm_pkg::*;
    import fwvip_<proto>_xtor_pkg::*;   // Phase 2 constants
    import fw_proto_<proto>_pkg::*;     // kit class layer (interface-classes + bridges)

    // Data/config first (they parameterize configs/sequences); then per-role files.
    `include "fwvip_<proto>_transaction.svh"
    // (optional) `include "fwvip_<proto>_framing.svh"
    // per role: config(+_p), [driver], [seq/item], agent …
    // (optional) `include "fwvip_<proto>_reg_adapter.svh"
endpackage
```

**The seam adapter is the role config** — the one pattern *every* role in *both* VIPs shares.
An abstract config (vif-agnostic; this is the type put in / fetched from the config DB) plus a
vif-aware specialization `*_config_p` that (1) holds the kit vif, (2) constructs a kit
`<proto>_<role>_xtor_bridge`, (3) implements/forwards the kit method API, (4) has a static
`set()` into the config DB:

```sv
// Abstract (components depend only on this):
class fwvip_uart_tx_config extends uvm_object;
    `uvm_object_utils(fwvip_uart_tx_config)
    function new(string name="fwvip_uart_tx_config"); super.new(name); endfunction
    virtual task send(bit [MAX_DATA_BITS-1:0] data);     endtask
    virtual task configure(fwvip_uart_framing f);        endtask
endclass

// vif-aware specialization (the seam adapter):
class fwvip_uart_tx_config_p #(type vif_t=int) extends fwvip_uart_tx_config;
    typedef fwvip_uart_tx_config_p #(vif_t) this_t;
    vif_t               vif;
    uart_tx_xtor_bridge m_bridge;        // kit provider: implements uart_tx_if + config

    static function void set(uvm_component ctxt, string inst, string field, vif_t vif);
        this_t cfg = new(); cfg.vif = vif;
        uvm_config_db #(fwvip_uart_tx_config)::set(ctxt, inst, field, cfg);
    endfunction

    protected function void ensure();    // lazy build: any call order vs phasing
        if (m_bridge == null) m_bridge = new(vif);
    endfunction
    virtual task send(bit [MAX_DATA_BITS-1:0] data);
        ensure(); m_bridge.send(data);
    endtask
    virtual task configure(fwvip_uart_framing f);
        ensure();
        m_bridge.configure(f.divisor, f.word_bits, f.parity_en,
                           f.parity_even, f.parity_stick, f.stop_bits);
    endtask
endclass
```

A width-parameterized bus threads the widths: `class fwvip_wb_initiator_config_p #(type
vif_t=int, int ADDR_WIDTH=32, int DATA_WIDTH=32) extends fwvip_wb_initiator_config;`.

---

## Phase 6 — Wire each role by its pattern

### Generic active agent (used by every driving role)

```sv
class fwvip_<proto>_<role> extends uvm_agent;
    `uvm_component_utils(fwvip_<proto>_<role>)
    fwvip_<proto>_<role>_config              m_cfg;
    uvm_sequencer #(fwvip_<proto>_transaction) m_seqr;
    fwvip_<proto>_<role>_driver              m_driver;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(fwvip_<proto>_<role>_config)::get(this, "", "cfg", m_cfg))
            `uvm_fatal(get_type_name(), "missing cfg")
        m_seqr   = uvm_sequencer #(fwvip_<proto>_transaction)::type_id::create("m_seqr", this);
        m_driver = fwvip_<proto>_<role>_driver::type_id::create("m_driver", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        m_driver.seq_item_port.connect(m_seqr.seq_item_export);
    endfunction
endclass
```

### Pattern A — Call-driven (WB initiator, UART tx)

```sv
// driver run_phase: pull item, call the config, done. No background thread.
task run_phase(uvm_phase phase);
    fwvip_<proto>_transaction t;
    forever begin
        seq_item_port.get_next_item(t);
        m_cfg.send(t.data);                 // UART
        // m_cfg.access(t);                 // WB (see below)
        seq_item_port.item_done();
    end
endtask
```
```sv
// WB initiator config_p.access(): drive request, capture response in place.
virtual task access(fwvip_wb_transaction t);
    bit[DATA_WIDTH_MAX-1:0] dat_t;
    vif.request(t.adr, t.dat, t.sel, t.we);
    vif.response(dat_t, t.err);
    if (!t.we) t.dat = dat_t;
endtask
```

### Pattern B — Callback responder (request/response only: WB target)

The kit bridge polls the request FIFO and *calls* a callback per request; the VIP rides it
into a responder sequence. Four cooperating pieces:

```sv
// (1) responder API + (2) wrapper item (UVM forbids sending a sequence to start_item)
interface class fwvip_wb_target_if;
    pure virtual task access(fwvip_wb_transaction t);
endclass
class fwvip_wb_target_item extends uvm_sequence_item implements fwvip_wb_target_if;
    `uvm_object_utils(fwvip_wb_target_item)
    fwvip_wb_target_if handler;
    function new(string name="fwvip_wb_target_item"); super.new(name); endfunction
    virtual task access(fwvip_wb_transaction t); if (handler!=null) handler.access(t); endtask
endclass
```
```sv
// (3) config_p: implements the kit's exact-width API, owns the bridge, bridges to MAX-width
class fwvip_wb_target_config_p #(type vif_t=int, int ADDR_WIDTH=32, int DATA_WIDTH=32)
        extends fwvip_wb_target_config implements wb_proto_if #(ADDR_WIDTH, DATA_WIDTH);
    vif_t                                           vif;
    wb_target_xtor_bridge #(ADDR_WIDTH, DATA_WIDTH) m_bridge;
    fwvip_wb_target_driver                          m_drv;
    virtual task start(fwvip_wb_target_driver drv);
        m_drv = drv; m_bridge = new(vif, this); m_bridge.start();  // forks wait_req->access->send_rsp
    endtask
    virtual task access(input [ADDR_WIDTH-1:0] adr, input [DATA_WIDTH-1:0] dat_w,
                        input [(DATA_WIDTH/8)-1:0] sel, input we,
                        output [DATA_WIDTH-1:0] dat_r, output err);
        fwvip_wb_transaction t = fwvip_wb_transaction::type_id::create("t");
        t.adr=adr; t.dat=dat_w; t.sel=sel; t.we=we;
        m_drv.service(t);                       // -> sequencer -> responder.handle_request
        dat_r = t.dat[DATA_WIDTH-1:0]; err = t.err;
    endtask
endclass
```
```sv
// (4) driver: just start the bridge and stay resident; service() rendezvous with the seq
task run_phase(uvm_phase phase); m_cfg.start(this); wait fork; endtask
task service(fwvip_wb_transaction t);
    fwvip_wb_target_item it;
    seq_item_port.get_next_item(it); it.access(t); seq_item_port.item_done();
endtask
// responder sequence: extend & override handle_request(); it sends the wrapper item forever.
class fwvip_wb_target_seq extends uvm_sequence #(fwvip_wb_target_item)
        implements fwvip_wb_target_if;
    virtual task handle_request(fwvip_wb_transaction t); endtask
    virtual task access(fwvip_wb_transaction t); handle_request(t); endtask
    task body();
        fwvip_wb_target_item it = fwvip_wb_target_item::type_id::create("it");
        it.handler = this;
        forever begin start_item(it); finish_item(it); end
    endtask
endclass
```
Flow: **bus → kit bridge → config.access() → driver.service() → sequencer → handle_request()**.

### Pattern C — Passive analysis producer

The agent owns a `uvm_analysis_port`, hands it to the config, and the config republishes. Two
delivery flavors — use whichever the kit offers.

```sv
// C1 push-callback (UART rx/monitor): kit bridge forks run() and CALLS our recv()/observe().
class fwvip_uart_rx_config_p #(type vif_t=int) extends fwvip_uart_rx_config
        implements uart_rx_if;
    vif_t               vif;
    uart_rx_xtor_bridge m_bridge;
    virtual task start();
        m_bridge = new(vif, this);   // 'this' is the sink (implements uart_rx_if)
        m_bridge.start();            // forks: vif.recv -> this.recv
    endtask
    virtual task recv(input [MAX_DATA_BITS-1:0] data, input [STATUS_BITS-1:0] status);
        fwvip_uart_transaction t;
        while (m_stall) @(posedge vif.clock);     // optional backpressure -> provoke overrun
        t = fwvip_uart_transaction::type_id::create("rx");
        t.data=data; t.status=status; t.is_tx=1'b0;
        if (ap != null) ap.write(t);
    endtask
endclass
// agent: ap = new(...); connect_phase: m_cfg.set_ap(ap); run_phase: m_cfg.start();
```
```sv
// C2 poll-loop (WB monitor): agent loops the blocking vif task.
task run_phase(uvm_phase phase);
    bit[ADDR_WIDTH_MAX-1:0] adr; bit[DATA_WIDTH_MAX-1:0] dat;
    bit[(DATA_WIDTH_MAX/8)-1:0] sel; bit we, err;
    m_cfg.wait_reset();
    forever begin
        m_cfg.wait_txn(adr, dat, sel, we, err);   // config_p delegates to vif.wait_txn
        t = fwvip_wb_transaction::type_id::create("t");
        t.adr=adr; t.dat=dat; t.sel=sel; t.we=we; t.err=err;
        ap.write(t);
    end
endtask
```

---

## Phase 7 — Register adapter  *(memory-mapped protocols only)*

```sv
class fwvip_wb_reg_adapter extends uvm_reg_adapter;
    `uvm_object_utils(fwvip_wb_reg_adapter)
    function new(string name="fwvip_wb_reg_adapter"); super.new(name); endfunction
    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
        fwvip_wb_transaction t = fwvip_wb_transaction::type_id::create("t");
        t.adr=rw.addr[ADDR_WIDTH_MAX-1:0]; t.dat=rw.data[DATA_WIDTH_MAX-1:0];
        t.we=(rw.kind==UVM_WRITE); t.sel='1; return t;
    endfunction
    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
        fwvip_wb_transaction t;
        if (!$cast(t, bus_item)) `uvm_fatal("ADAPT","not a fwvip_wb_transaction")
        rw.addr=t.adr; rw.data=t.dat; rw.kind=(t.we)?UVM_WRITE:UVM_READ;
        rw.status=(t.err)?UVM_NOT_OK:UVM_IS_OK; rw.n_bits=DATA_WIDTH_MAX;
    endfunction
endclass
```
UART (no addresses) skips this.

---

## Phase 8 — Register macros

One-line config-DB binding; threaded args are protocol-shaped:

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

## Phase 9 — Python / cocotb front-end

A backend-independent front-end so the same VIP drives cocotb (or pure-Python / DPI). Three
thin layers + a cocotb backend.

```python
# transaction.py — dataclasses + a Layout that (un)packs RV vectors (MSB-first, matching the
# kit's packed structs). A *held* runtime config is NOT a streamed vector — carry it as a
# plain dataclass driven onto the core's cfg_* ports.
class WbLayout:
    def __init__(self, addr_width=32, data_width=32):
        self.aw, self.dw, self.sw = addr_width, data_width, data_width // 8
    def pack_req(self, req):
        return ((req.adr << (self.dw+1+self.sw)) | (req.dat << (1+self.sw))
                | ((1 if req.we else 0) << self.sw) | (req.sel & ((1<<self.sw)-1)))
    def unpack_rsp(self, bits):
        return WbRsp(dat=(bits >> 1) & ((1<<self.dw)-1), err=bool(bits & 1))
```
```python
# backend.py — ABCs that only move bits + expose reset (+ configure() for held config).
# Shape follows the streams: a paired bus has push_request/pop_response; independent one-way
# streams have role-specific push_char/pop_char/pop.
class InitiatorBackend(Backend):
    @abstractmethod
    async def push_request(self, data: int) -> None: ...
    @abstractmethod
    async def pop_response(self) -> int: ...
```
```python
# <role>.py — friendly front-end over a backend.
class WbInitiator:
    def __init__(self, backend, addr_width=32, data_width=32):
        self._b = backend; self.layout = WbLayout(addr_width, data_width)
    async def request(self, req):
        await self._b.push_request(self.layout.pack_req(req))
        return self.layout.unpack_rsp(await self._b.pop_response())
    async def write(self, adr, dat, sel=None): return await self.request(WbReq(adr,dat,True,sel))
    async def read(self,  adr, sel=None):      return await self.request(WbReq(adr,0,False,sel))
```
```python
# cocotb/backend.py — bound to a transactor CORE handle (dut.u_<role>); drives RV ports with
# the canonical event-driven primitives (idle: sleep on the signal edge; transfer+settle on
# clock edges). Held config is written straight to cfg_* ports.
class _Base:
    async def _rv_get(self, valid, dat):
        if not _ival(valid): await RisingEdge(valid)     # idle
        data = int(dat.value)
        await RisingEdge(self.clock); await RisingEdge(self.clock)  # transfer + settle
        return data
    async def _rv_put(self, valid, ready, dat, value):
        dat.value = value; valid.value = 1
        if not _ival(ready): await RisingEdge(ready)
        await RisingEdge(self.clock); valid.value = 0; await RisingEdge(self.clock)
```
See `fwvip-core/docs/cocotb-performance.md` for *why* this is event-driven.

---

## Phase 10 — Bench wiring + reset synchronization

`hdl_top` instantiates the kit wrappers + fwvip-core clock/reset interfaces (+ any
protocol-specific injection interface); `hvl_top` binds them and runs the test:

```sv
// hdl_top: kit transactor wrappers on a shared bus + clock/reset transactor interfaces
wb_initiator_xtor #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) u_initiator (.clock, .reset, /*bus*/);
wb_target_xtor    #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) u_target    (.clock, .reset, /*bus*/);
wb_monitor_xtor   #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) u_monitor   (.clock, .reset, /*bus*/);
fwvip_clock_xtor_if            u_clk_if (.clock, .reset);
fwvip_reset_xtor_if #(.ACTIVE(1)) u_rst_if (.clock, .reset);
```
```sv
// hvl_top: register macros + clock/reset providers + run_test
initial begin
    `fwvip_wb_initiator_register(32, 32, u_hdl.u_initiator.u_if, "uvm_test_top.m_env.m_init*");
    `fwvip_wb_target_register   (32, 32, u_hdl.u_target.u_if,    "uvm_test_top.m_env.m_targ*");
    `fwvip_wb_monitor_register  (32, 32, u_hdl.u_monitor.u_if,   "uvm_test_top.m_env.m_mon*");
    fwvip_clock_config_p#(virtual fwvip_clock_xtor_if    )::set(null,"uvm_test_top.m_env*","clock",u_hdl.u_clk_if);
    fwvip_reset_config_p#(virtual fwvip_reset_xtor_if#(1))::set(null,"uvm_test_top.m_env*","reset",u_hdl.u_rst_if);
    run_test();
end
```

> **Reset comes from the fwvip-core providers, never a fixed delay.** The env retrieves the
> reset/clock providers and the base virtual sequence waits on reset before stimulus.

The **env** builds the agents + a virtual sequencer + a scoreboard, wires the vseqr to the
sub-sequencers/configs, and connects analysis ports. Scoreboard topology is protocol-shaped
(WB: the single monitor stream; UART: TX-line monitor tap = reference, RX = delivered). The
reusable sequence library (memory responder, single-access, virtual sequences) lives in the
test/env package — **not** the VIP package.

---

## Phase 11 — DFM packaging & tests

```yaml
# flow.yaml
package:
  name: org.fwvip.<proto>
  imports:
  - "${{ rootdir }}/../fw-proto-<proto>/flow.yaml"
  - "${{ rootdir }}/../fwvip-core/flow.yaml"
  fragments: [src/vip.yaml, tests/flow.yaml]
```
```yaml
# src/vip.yaml — constants pkg first, then the UVM pkg (needs the kit class layer)
fragment:
  tasks:
  - export: xtor-pkg
    uses: std.FileSet
    with: {type: systemVerilogSource, base: uvm, incdirs: ["."], include: [fwvip_<proto>_xtor_pkg.sv]}
  - name: vip-uvm-hvlsrc
    needs: [xtor-pkg, fw.proto.<proto>.class, fw.proto.<proto>.xtor-sv]  # UART: fw.proto.uart.files
    uses: std.FileSet
    with: {type: systemVerilogSource, base: uvm, incdirs: ["."], include: [fwvip_<proto>_pkg.sv]}
```
Include only the package compilation unit (`fwvip_<proto>_pkg.sv`); the `.svh` classes come in
via the incdir (globbing `*.sv` double-compiles the constants pkg). UVM scenarios run one image
+ test class selected by `+SEQ=<vseq>`; the cocotb flow uses `dv-flow-libcocotb` and needs the
kit's `xtor-core`; formal TBs consume the kit's `<proto>_proto_checker` (the VIP vendors none).

### Validate

```sh
dfm run org.fwvip.<proto>.uvm-test-smoke
dfm run org.fwvip.<proto>.cocotb-check
```

---

## Phase 12 — VIP usage skill  *(required, last)*

Every VIP ships `skills/fwvip-<proto>-usage/SKILL.md` — agent-facing instructions for connecting
and driving **this** VIP, written from the files you just created and verified (concrete role
set, class names, register macros, sequence/runtime-config/cocotb signatures — **not** generic).
Name the skill after the VIP (`fwvip-<proto>-usage`, e.g. `fwvip-wb-usage`, `fwvip-uart-usage`)
so it stays globally unique across VIPs.

```markdown
---
name: fwvip-<proto>-usage
description: Connect and drive the fwvip-<proto> Verification IP — bind its agents into a UVM
  env (register macros + config DB), write stimulus/responder sequences, apply runtime config,
  [run the reg-model front door,] and/or drive the cocotb front-end. Use when integrating
  fwvip-<proto> into a testbench or generating stimulus for it.
tools: Read, Write, Edit, Bash, Grep, Glob
---
```
Cover: what the VIP provides (the real role set), the DFM dependency
(`org.fwvip.<proto>.vip-uvm-hvlsrc`), hdl_top/hvl_top wiring with real arg lists, how to drive
the active role(s) and write responders/subscribe to consumers, runtime config *(if any)*, the
reg model *(if any)*, the cocotb front-end, the pitfalls below, and a runnable
`tests/uvm/` + `tests/cocotb/` example with `dfm run` commands.

---

## Pitfalls

- **Don't rebuild the kit.** Cores/interfaces/wrappers/bridges/method-API/checker are the kit's.
- **Let the protocol pick role shapes** — driving / responder / passive-consumer. No wire
  response ⇒ no responder, no reg model. A streaming receive side is a *passive consumer*.
- **Constants:** width-parameterized bus ⇒ `*_WIDTH_MAX` + `*_config_p #(vif_t,AW,DW)`; fixed
  carrier ⇒ plain localparams + `*_config_p #(vif_t)`.
- **The seam adapter is the config** — holds the vif, owns a kit bridge, forwards the kit API.
- **Passive ≠ responder** — a consumer republishes on an analysis port (push or poll); only a
  true request/response role uses the callback-responder + wrapper-item.
- **No `typedef virtual <if> #(…)` in procedural code** (Verilator crash) — bind via the
  `register` macros; access through the config. Use `always @(posedge clock)`, never
  `always_ff`, in any interface code you touch.
- **Reset from fwvip-core providers**, not fixed delays.
- **cocotb is event-driven** (`_rv_get`/`_rv_put`); drive held config onto `cfg_*` ports.

> Longer prose companion: `resources/skills/create_vip.md`. Worked code: the `fwvip-wb` and
> `fwvip-uart` packages.
