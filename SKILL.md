# fwvip-core — Agent Skill

`fwvip-core` (package `org.fwvip.core`, historically "fwvip-common") is the **shared
infrastructure** layer for building Featherweight **Verification IP (VIP)** — the
methodology layer (UVM agents, cocotb front-ends) that sits on top of protocol transactors.

It does **not** contain protocol transactors. Those live in the per-protocol transactor
kits (`fw-proto-<proto>`, e.g. `fw-proto-wb`) built by the **`fw-proto-create`** skill.
`fwvip-core` provides the pieces every VIP shares regardless of protocol.

## The two layers

| Layer | Package | Built by | Role |
|-------|---------|----------|------|
| **Transactor kit** | `fw-proto-<proto>` | `fw-proto-create` skill | Signal-level transactors (core ↔ pins + in-built FIFOs + task API), a method-level API + bridges, a protocol checker. Per-instance parameterized; usable in sim, formal, emulation. |
| **VIP / methodology** | `fwvip-<proto>` (e.g. `fwvip-wb`) | **`create_vip`** skill | A UVM agent set *and* a Python/cocotb front-end built on top of the kit. |
| **Shared infrastructure** | `fwvip-core` (this package) | — | Clock/reset transactors + UVM config providers, RV FIFO primitives, cocotb performance guidance. Consumed by every VIP. |

## What fwvip-core provides

### Clock / reset transactors + providers
The one piece of timing every VIP needs. A bench instantiates the signal-level interfaces
and exposes them to the UVM env through config providers:

- `fwvip_clock_xtor_if`, `fwvip_reset_xtor_if` — signal-level interfaces (export
  `clock-reset-xtor`).
- `fwvip_core_pkg` — the abstract, UVM-free APIs `fwvip_clock_if` / `fwvip_reset_if` /
  `fwvip_wait_reset_if` (export `core-pkg`); consumed by plain-SV TBs *and* the UVM layer.
- `fwvip_core_uvm_pkg` — the UVM config objects `fwvip_clock_config` / `fwvip_reset_config`
  retrieved from the config DB (export `core-uvm-pkg`).

A VIP env sources these providers and waits on the reset provider before driving stimulus —
replacing fixed-delay `wait_reset` hacks.

### Ready/valid FIFO primitives
`fwvip_sv_ingress_fifo` / `fwvip_sv_egress_fifo` (exports `ingress-fifo` / `egress-fifo`) —
generic clock-synchronous RV buffers with `put()`/`get()` tasks, available when a
methodology layer needs its own FIFO buffering.

### cocotb performance pattern
`docs/cocotb-performance.md` — the canonical event-driven ready/valid handshake (sleep on
the signal edge while idle; transfer + settle on clock edges) every Featherweight cocotb
backend uses.

## Build System: DV Flow Manager (DFM)

Tests and builds use the [DV Flow Manager](https://dv-flow.github.io/) (`dv_flow.mgr`). Each
directory has a `flow.yaml` declaring tasks (file sets, sim images, formal proofs) with
`needs:` dependencies. The `org.fwvip.core` package exports `core-pkg`, `core-uvm-pkg`,
`clock-reset-xtor`, `ingress-fifo`, and `egress-fifo`. A VIP package imports `fwvip-core`
(and its transactor kit) and declares `needs` on the exports it uses.

```sh
dfm run <fully.qualified.task.name> --root <tests-dir>      # run a task
dfm show tasks --root <tests-dir>                           # list tasks
```

## Important Constraints (Verilator)

These apply to any interface/transactor code a VIP or kit touches:

- Use `always @(posedge clock …)` in interfaces — **never** `always_ff`. Verilator 5.x
  crashes with `always_ff` inside interfaces.
- Do **not** declare `automatic logic` inside `always` blocks in interfaces. Use
  interface-level `reg` instead.
- Do **not** use `typedef virtual <if> #(P1, P2)` in procedural blocks — Verilator crashes.
  Bind virtual interfaces via the VIP's `*_register` macros (which call `*_config_p::set`)
  and access through the config / a direct hierarchical path.
- Driving a core's config ports with a continuous `assign` from a var written through a
  virtual-interface handle does not reliably re-trigger — drive from a **clocked copy**.

## Creating a VIP

Invoke the **`fwvip-create`** skill (`skills/fwvip-create/SKILL.md`) — a self-contained,
example-driven workflow for building the **VIP / methodology layer** on top of an existing
transactor kit. (A longer prose companion is at
[resources/skills/create_vip.md](resources/skills/create_vip.md).) Either covers:

- The two-layer model and what the VIP consumes from the kit
- The width seam (`*_WIDTH_MAX`, Decision D4) and the transaction item
- The UVM package: initiator (driver calls the transactor), target (transactor calls the
  responder via the kit bridge), monitor, reg adapter, and `*_register` macros
- The Python/cocotb front-end (backend-independent layout + cocotb backend)
- Bench wiring + reset synchronization via this package's clock/reset providers
- DFM packaging, tests, and the required per-VIP **`vip-usage`** skill

Two validated VIPs calibrate the skill: **`fwvip-wb`** (a synchronous, memory-mapped bus —
request/response, width-parameterized, register model) and **`fwvip-uart`** (an asynchronous
streaming line protocol — one-way TX/RX, fixed carrier, runtime framing, no register model).
Together they show which choices the protocol drives.

> Building the *transactor kit* itself (cores, interfaces, wrappers, checker) is a different
> job — use the **`fw-proto-create`** skill for that.
