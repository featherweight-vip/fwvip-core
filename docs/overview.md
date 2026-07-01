# Overview

Featherweight VIP (FWVIP) splits protocol support into two layers with a clean seam, so the
hard protocol/timing reasoning is solved **once** and reused by every methodology.

## The transactor kit (`fw-proto-<proto>`)

- A signal-level **transactor core** implements bus semantics once, independent of
  methodology, and is **formally verified**.
- The core exposes ready/valid ("FIFO") channels: a request channel and a response channel
  (and a monitor egress channel for the passive role).
- Roles are split cleanly: **initiator**, **target**, **monitor**. Each has a core, a
  hand-coded SV interface with an in-built FIFO + blocking task API, a thin wrapper, and a
  method-level bridge.
- A reusable **protocol checker** ships with the kit.
- Built by the `fw-proto-create` skill. For Wishbone this is `fw-proto-wb` (e.g.
  `wb_initiator_xtor` / `wb_target_xtor` / `wb_monitor_xtor`).

## The VIP / methodology layer (`fwvip-<proto>`)

- Thin methodology layers wrap the kit's transactors: a **UVM** agent set and a
  **Python/cocotb** front-end. Because the timing is solved in the verified core, the
  transactors and tests built on top are correct and fast by construction.
- Built by the `create_vip` skill. For Wishbone this is `fwvip-wb`.

## Shared infrastructure (`fwvip-core`, this package)

- Clock/reset transactors and their UVM config providers (for reset synchronization),
  generic ready/valid FIFO primitives, and the cocotb performance pattern — the pieces every
  VIP needs regardless of protocol.
