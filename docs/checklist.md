# Authoring checklist

A checklist for building a Featherweight **VIP** (`fwvip-<proto>`) on top of an existing
transactor kit. (Building the kit itself — cores, interfaces, wrappers, checker — is the
`fw-proto-create` skill; not covered here.)

- **Prerequisite: the transactor kit exists**
  - `fw-proto-<proto>` provides the `<proto>_<role>_xtor` wrappers (with a `u_if` task API),
    the cores' ready/valid ports, the `<proto>_proto_if` method API + `*_xtor_bridge`
    classes, and the protocol checker. The VIP consumes these; it does not rebuild them.
- **Width policy**
  - A small `fwvip_<proto>_xtor_pkg` defines `ADDR_WIDTH_MAX` / `DATA_WIDTH_MAX` (Decision
    D4) used to size all VIP class fields.
- **UVM package**
  - Agent per role: initiator and target `uvm_agent`s (sequencer + driver), plus a passive
    monitor agent.
  - Config per role: an abstract config + a `*_config_p #(vif_t, AW, DW)` holding the typed
    vif, with a static `set()` for `uvm_config_db`; components fetch `"cfg"` in `build_phase`.
  - Transaction item + sequences; a reusable memory responder lives in the test/env library.
  - Register adapter (`uvm_reg_adapter`) for memory-style protocols.
- **Initiator vs. target wiring**
  - Initiator: the driver *calls* the transactor (`vif.request(...)` / `vif.response(...)`).
  - Target: the kit bridge polls the FIFOs and *calls* the responder via
    `config.access()` → `driver.service()` → sequencer → `handle_request()` (no bus polling).
- **Virtual interface flow**
  - The bench instantiates the `<proto>_<role>_xtor` wrappers and calls
    `fwvip_<proto>_<role>_register(AW, DW, u_hdl.u_<role>.u_if, inst)` (which invokes
    `*_config_p::set`); the agent/driver retrieves `"cfg"` from `uvm_config_db`.
  - Avoid `typedef virtual <if> #(AW,DW)` in procedural code (Verilator crash) — use the
    register macros.
- **Reset synchronization**
  - Source the `fwvip-core` clock/reset providers (`fwvip_clock_config` /
    `fwvip_reset_config`); the base virtual sequence waits on reset before stimulus.
- **Monitor**
  - Passive: loops `wait_txn(...)` and publishes observed transactions on a
    `uvm_analysis_port`.
- **Python/cocotb front-end**
  - Backend-independent layer (`org.fwvip.<proto>`: dataclasses + RV bit layout + backend
    ABCs + friendly front-ends) plus a cocotb backend bound to the transactor *core* handle.
- **Documentation and examples**
  - A short integration example (bench wiring, register macros, starting sequences, cocotb
    front-end), and the required per-VIP **`vip-usage`** skill.
