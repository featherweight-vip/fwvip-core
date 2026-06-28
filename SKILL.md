# fwvip-common — Agent Skill

`fwvip-common` is a framework for building lightweight, synthesizable Verification IP (VIP) components for digital hardware protocols. The framework emphasises portability — all transactor cores use plain signal-level ports (no interfaces, no macros) so they work in simulation, formal verification, emulation, and synthesizable assertions.

## Key Concepts

### Three-Tier Transactor Architecture

Every VIP built on this framework follows a three-tier structure:

1. **Core transactor** (`*_core.sv`) — Pure RTL module. Signal-level ports only. Implements FSMs that convert between ready/valid FIFO signals and the protocol-specific bus signals. No SV interfaces, no macros.

2. **SV interface** (`*_if.sv`) — A `SystemVerilog interface` that wraps two shared FIFO primitives (`fwvip_sv_ingress_fifo` and `fwvip_sv_egress_fifo`) and exposes `task`-based API calls (`put()`, `get()`) for the testbench to call.

3. **SV wrapper module** (`*_sv.sv`) — A thin `module` that instantiates both the core and the SV interface, connecting the ready/valid wires between them. Exposes the protocol bus signals as normal module ports.

Each VIP provides three transactors: **Initiator**, **Target**, and **Monitor**.

### FIFO-Based Stream Abstraction

The core transactors communicate through simple ready/valid FIFO ports:

- **Ingress FIFO** (`req_valid` / `req_data` / `req_ready`): the transactor consumes data from this FIFO.
- **Egress FIFO** (`rsp_valid` / `rsp_data` / `rsp_ready`): the transactor produces data into this FIFO.

Shared SV interfaces `fwvip_sv_ingress_fifo` and `fwvip_sv_egress_fifo` (in `src/sv/`) implement clock-synchronous buffering with `put()` and `get()` tasks. VIP-specific interfaces (`*_if.sv`) instantiate these and delegate to them.

### Build System: DV Flow Manager (DFM)

Tests and builds use the [DV Flow Manager](https://dv-flow.github.io/) (`dv_flow.mgr`). Each directory contains a `flow.yaml` that declares tasks (file sets, simulation images, formal proofs). Tasks declare `needs:` to express dependencies. The `org.fwvip.common` package exports `ingress-fifo` and `egress-fifo` tasks; VIP packages import `fwvip-common` and declare `needs` on those tasks in their own `initiator-sv`, `target-sv`, and `monitor-sv` export tasks.

Run a test from a wishbone test directory:
```sh
packages/python/bin/python -m dv_flow.mgr run <fully.qualified.task.name> --root resources/example/wishbone/tests/
```

List available tasks with `dfm show tasks --root <tests-dir>`. Wishbone tasks: `org.featherweight-vip.wishbone.tests.sim.b2b-sim`, `…b2b-sv-sim`, `…formal.wb-b2b-bmc`.

## Important Constraints (Verilator)

- Use `always @(posedge clock …)` in interfaces — **never** `always_ff`. Verilator 5.x crashes with `always_ff` inside interfaces.
- Do **not** declare `automatic logic` inside `always` blocks in interfaces. Use interface-level `reg` instead.
- Do **not** use `typedef virtual <if> #(P1, P2)` in procedural blocks — Verilator crashes. Access interface tasks via direct hierarchical path: `u_module.bfm_if.task_name(args)`.

## Creating a New VIP

See **[resources/skills/create_vip.md](resources/skills/create_vip.md)** for the full step-by-step workflow, including:
- Protocol analysis and stream decomposition
- FSM design guidelines for core transactors
- Required directory layout and file naming conventions
- SV interface and wrapper patterns
- Testing requirements (simulation, formal)
- `flow.yaml` integration patterns

The **Wishbone B.3** example at `resources/example/wishbone/` is the canonical reference implementation. It implements a complete initiator/target/monitor VIP with simulation and formal tests.
