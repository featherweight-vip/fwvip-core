Featherweight VIP checklist

- Protocol cores
  - initiator_core: request-in, response-out, drives bus; single outstanding transfer.
  - target_core: observes bus, emits request, accepts response, asserts ACK/ERR.
- Methodology wrappers
  - driver_bfm and monitor_bfm that bind to the protocol interface and expose role-specific tasks plus configure().
  - Common BFM package for shared parameters (for example, ADDR_WIDTH_MAX/DATA_WIDTH_MAX) and optional struct macros.
- UVM package
  - Agent per role (initiator, target) with sequencer and driver.
  - Config per role holding a typed vif and helper set() for uvm_config_db; drivers fetch "cfg" in build_phase.
  - Transaction and base sequences.
  - Register adapter for memory-style protocols.
- Virtual interface flow
  - Testbench creates vif, calls role_config_p::set(ctxt, inst, "cfg", vif); agent/driver retrieves "cfg" from uvm_config_db.
- Monitor
  - Passive monitor BFM that publishes captured transactions via a proxy callback.
- Documentation and examples
  - Provide a short integration example showing BFM-to-DUT binding, config set(), and starting sequences.
