class fwvip_wb_monitor extends uvm_monitor;
  `uvm_component_utils(fwvip_wb_monitor)

  fwvip_wb_mon_cfg cfg;
  uvm_analysis_port #(fwvip_wb_mon_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    ap = new("ap", this);
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      fwvip_wb_mon_item item;
      cfg.do_get(item);
      ap.write(item);
    end
  endtask

endclass
