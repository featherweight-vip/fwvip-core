class fwvip_wb_b2b_env extends uvm_env;
  `uvm_component_utils(fwvip_wb_b2b_env)

  fwvip_wb_init_agent init_agent;
  fwvip_wb_mon_agent  mon_agent;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    init_agent = fwvip_wb_init_agent::type_id::create("init_agent", this);
    mon_agent  = fwvip_wb_mon_agent::type_id::create("mon_agent",  this);
  endfunction

endclass
