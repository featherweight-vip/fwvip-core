class fwvip_wb_mon_agent extends uvm_agent;
  `uvm_component_utils(fwvip_wb_mon_agent)

  fwvip_wb_mon_cfg     cfg;
  fwvip_wb_monitor     mon;
  uvm_analysis_port #(fwvip_wb_mon_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(fwvip_wb_mon_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "fwvip_wb_mon_cfg not found in config_db")
    mon = fwvip_wb_monitor::type_id::create("mon", this);
    mon.cfg = cfg;
    ap = new("ap", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    mon.ap.connect(ap);
  endfunction

endclass
