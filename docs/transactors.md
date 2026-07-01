# Transactors

## Protocol transactors live in the kit

The signal-level **protocol** transactors (initiator / target / monitor) — cores that
convert ready/valid ("FIFO") streams to bus pins, their SV interfaces, wrappers, method-API
bridges, and the protocol checker — are **not** part of `fwvip-core`. They live in the
per-protocol transactor kit `fw-proto-<proto>` and are built by the `fw-proto-create` skill.
See that kit's documentation for the core FSMs, the RV request/response/monitor vector
packing, and the bridge classes the VIP consumes.

## Clock / reset transactors (provided here)

`fwvip-core` provides the timing transactors every VIP needs:

- **`fwvip_clock_xtor_if`** — exposes the clock to the methodology layer via the abstract
  `fwvip_clock_if` API.
- **`fwvip_reset_xtor_if #(.ACTIVE())`** — exposes reset state via `fwvip_reset_if` /
  `fwvip_wait_reset_if` (notably `wait_reset()`), so a VIP env can synchronize to reset
  deassertion instead of using a fixed delay.

These signal-level interfaces are adapted to UVM through the config providers in
`fwvip_core_uvm_pkg` (`fwvip_clock_config` / `fwvip_reset_config`): the bench instantiates
the interfaces, sets the providers into the config DB, and the env retrieves them.

## Monitor role

The monitor role (in any kit) is always **passive** and never drives pins.
