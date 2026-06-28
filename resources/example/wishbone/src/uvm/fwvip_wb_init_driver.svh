class fwvip_wb_init_driver extends uvm_driver #(fwvip_wb_seq_item);
  `uvm_component_utils(fwvip_wb_init_driver)

  fwvip_wb_init_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      fwvip_wb_seq_item item;
      seq_item_port.get_next_item(item);
      cfg.do_req(item.adr, item.dat, item.we, item.rsp_dat, item.rsp_err);
      seq_item_port.item_done();
    end
  endtask

endclass
