// UVM environment for the reactive back-to-back target test.
// Contains an initiator agent, a target agent, and a monitor agent.
class fwvip_wb_b2b_targ_env extends uvm_env;
  `uvm_component_utils(fwvip_wb_b2b_targ_env)

  fwvip_wb_init_agent init_agent;
  fwvip_wb_targ_agent targ_agent;
  fwvip_wb_mon_agent  mon_agent;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    fwvip_wb_init_cfg init_cfg;
    fwvip_wb_targ_cfg targ_cfg;
    fwvip_wb_mon_cfg  mon_cfg;

    if (!uvm_config_db #(fwvip_wb_init_cfg)::get(
            this, "init_agent", "cfg", init_cfg))
      `uvm_fatal("CFG", "No init_cfg in config_db")
    if (!uvm_config_db #(fwvip_wb_targ_cfg)::get(
            this, "targ_agent", "cfg", targ_cfg))
      `uvm_fatal("CFG", "No targ_cfg in config_db")
    if (!uvm_config_db #(fwvip_wb_mon_cfg)::get(
            this, "mon_agent", "cfg", mon_cfg))
      `uvm_fatal("CFG", "No mon_cfg in config_db")

    init_agent = fwvip_wb_init_agent::type_id::create("init_agent", this);
    targ_agent = fwvip_wb_targ_agent::type_id::create("targ_agent", this);
    mon_agent  = fwvip_wb_mon_agent::type_id::create("mon_agent",  this);

    init_agent.cfg = init_cfg;
    targ_agent.cfg = targ_cfg;
    mon_agent.cfg  = mon_cfg;
  endfunction

endclass
