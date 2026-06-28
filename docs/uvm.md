UVM methodology package elements

- Packages and types
  - fwvip_wb_pkg imports BFM types and includes agents, configs, drivers, sequences, transaction, and a uvm_reg_adapter.
- Agents per role
  - fwvip_wb_initiator and fwvip_wb_target are uvm_agent components with a sequencer and role-specific driver.
  - A passive monitor can be supplied via interface-based monitor BFMs or a UVM monitor that consumes their callbacks.
- Passing the transactor virtual interface
  - Each role has a config class with a parameterized subtype that carries a typed vif handle to the methodology wrapper.
  - Helper set() places the config in uvm_config_db under the field "cfg"; agents/drivers retrieve it in build_phase.
  - VIF tasks used by drivers: initiator uses request(adr, dat, sel, we) and response(dat, err); target uses wait_req(adr, dat, sel, we) and send_rsp(dat, err); both provide wait_reset().
- Registration macros
  - Use `uvm_component_utils for agents/drivers and `uvm_object_utils for configs/transactions/adapters.
  - Core wrappers standardize signatures using macros like `fwvip_bfm_t/`fwvip_bfm_t_end.
- Register layer
  - Include a uvm_reg_adapter that maps uvm_reg_bus_op to the VIP transaction and vice versa (see fwvip_wb_reg_adapter as a template).
