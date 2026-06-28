class fwvip_wb_init_agent extends uvm_agent;
  `uvm_component_utils(fwvip_wb_init_agent)

  fwvip_wb_init_cfg    cfg;
  fwvip_wb_init_seqr   seqr;
  fwvip_wb_init_driver drv;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db #(fwvip_wb_init_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NO_CFG", "fwvip_wb_init_cfg not found in config_db")
    if (get_is_active() == UVM_ACTIVE) begin
      seqr = fwvip_wb_init_seqr::type_id::create("seqr", this);
      drv  = fwvip_wb_init_driver::type_id::create("drv",  this);
      drv.cfg = cfg;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction

endclass
