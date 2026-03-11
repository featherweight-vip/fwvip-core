// Unparameterized base config for the target agent.
virtual class fwvip_wb_targ_cfg extends uvm_object
    implements fwvip_wb_targ_op_api;

  int unsigned addr_width = FWVIP_WB_ADDR_WIDTH_MAX;
  int unsigned data_width = FWVIP_WB_DATA_WIDTH_MAX;

  function new(string name = "fwvip_wb_targ_cfg");
    super.new(name);
  endfunction

  pure virtual task req_get(
    output bit [FWVIP_WB_ADDR_WIDTH_MAX-1:0] adr,
    output bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] dat,
    output bit                               we
  );

  pure virtual task rsp_put(
    input  bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] rsp_dat,
    input  bit                               rsp_err
  );

endclass
