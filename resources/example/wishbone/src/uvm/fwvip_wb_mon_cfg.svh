// Unparameterized base config for the monitor agent.
virtual class fwvip_wb_mon_cfg extends uvm_object
    implements fwvip_wb_mon_op_api;

  int unsigned addr_width = FWVIP_WB_ADDR_WIDTH_MAX;
  int unsigned data_width = FWVIP_WB_DATA_WIDTH_MAX;

  function new(string name = "fwvip_wb_mon_cfg");
    super.new(name);
  endfunction

  pure virtual task do_get(output fwvip_wb_mon_item item);

endclass
