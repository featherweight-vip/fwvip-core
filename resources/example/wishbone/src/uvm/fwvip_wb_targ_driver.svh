// Target driver — handler-sequence pattern.
//
// Each UVM sequence item serves a dual role:
//   • Item sent TO the driver carries rsp_dat/rsp_err for the PREVIOUS request.
//   • The driver blocks on cfg.req_get(), populates item.adr/dat/we, and
//     returns the item to the sequence so it can compute the next response.
//
// On the very first iteration there is no previous response to send; the
// driver skips rsp_put() and goes straight to req_get().
class fwvip_wb_targ_driver extends uvm_driver #(fwvip_wb_seq_item);
  `uvm_component_utils(fwvip_wb_targ_driver)

  fwvip_wb_targ_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    fwvip_wb_seq_item item;
    bit first = 1'b1;
    forever begin
      seq_item_port.get_next_item(item);
      if (!first)
        cfg.rsp_put(item.rsp_dat, item.rsp_err);
      first = 1'b0;
      cfg.req_get(item.adr, item.dat, item.we);
      seq_item_port.item_done();
    end
  endtask

endclass
