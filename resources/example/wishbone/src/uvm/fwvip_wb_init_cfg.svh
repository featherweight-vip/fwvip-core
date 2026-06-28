// Unparameterized base config for the initiator agent.
// Stored in uvm_config_db and held by drivers/agents without exposing
// the BFM width parameters.  The actual implementation is in
// fwvip_wb_init_cfg_t (the parameterised extension).
virtual class fwvip_wb_init_cfg extends uvm_object
    implements fwvip_wb_init_op_api;

  int unsigned addr_width = FWVIP_WB_ADDR_WIDTH_MAX;
  int unsigned data_width = FWVIP_WB_DATA_WIDTH_MAX;

  function new(string name = "fwvip_wb_init_cfg");
    super.new(name);
  endfunction

  pure virtual task do_req(
    input  bit [FWVIP_WB_ADDR_WIDTH_MAX-1:0] adr,
    input  bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] dat,
    input  bit                               we,
    output bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] rsp_dat,
    output bit                               rsp_err
  );

endclass
