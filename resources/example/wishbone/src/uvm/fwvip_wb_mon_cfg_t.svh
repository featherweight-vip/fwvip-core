// Parameterised config extension for the monitor agent.
// Calls vif.get() and unpacks the MON_STRUCT into a fwvip_wb_mon_item.
class fwvip_wb_mon_cfg_t #(
  int ADDR_WIDTH = 32,
  int DATA_WIDTH = 32
) extends fwvip_wb_mon_cfg;

  virtual fwvip_wb_monitor_if #(ADDR_WIDTH, DATA_WIDTH) vif;

  function new(string name = "fwvip_wb_mon_cfg_t");
    super.new(name);
    addr_width = ADDR_WIDTH;
    data_width = DATA_WIDTH;
  endfunction

  virtual task do_get(output fwvip_wb_mon_item item);
    `FWVIP_WB_MON_STRUCT(ADDR_WIDTH, DATA_WIDTH) mon_s;
    bit [`FWVIP_WB_MON_WIDTH(ADDR_WIDTH, DATA_WIDTH)-1:0] raw;

    item = fwvip_wb_mon_item::type_id::create("mon_item");
    vif.get(raw);
    mon_s        = raw;
    item.adr     = {{(FWVIP_WB_ADDR_WIDTH_MAX-ADDR_WIDTH){1'b0}}, mon_s.adr};
    item.dat     = {{(FWVIP_WB_DATA_WIDTH_MAX-DATA_WIDTH){1'b0}}, mon_s.dat};
    item.err     = mon_s.err;
    item.we      = mon_s.we;
    item.cyc_len = mon_s.cyc_len;
  endtask

endclass
