// Handler sequence for the target agent.
//
// Implements a simple word-addressed memory model.  On each iteration:
//   1. Driver skips rsp_put (first=1) or sends rsp for previous request.
//   2. Driver calls req_get, populates item.adr/dat/we.
//   3. Sequence services the request: writes update mem[], reads return mem[].
//   4. Next item carries the computed response.
//
// The sequence handles exactly n_ops requests then sends a final response
// and exits (the driver's forever loop is killed when run_phase ends).
class fwvip_wb_targ_handler_seq extends uvm_sequence #(fwvip_wb_seq_item);
  `uvm_object_utils(fwvip_wb_targ_handler_seq)

  int n_ops = 8;  // number of requests to handle before stopping
  bit [31:0] err_addrs[];
  bit        err_on_reads_only = 1'b1;

  function new(string name = "fwvip_wb_targ_handler_seq");
    super.new(name);
  endfunction

  function bit should_error(bit [31:0] addr, bit we);
    if (err_on_reads_only && we)
      return 1'b0;
    foreach (err_addrs[i]) begin
      if (err_addrs[i] == addr)
        return 1'b1;
    end
    return 1'b0;
  endfunction

  task body();
    fwvip_wb_seq_item item;
    bit [31:0] mem_model[bit [31:0]];  // sparse word-addressed memory

    // ----------------------------------------------------------------
    // First item: no previous response to send (driver uses first=1).
    // Driver blocks on req_get and returns the observed request.
    // ----------------------------------------------------------------
    item = fwvip_wb_seq_item::type_id::create("item");
    item.rsp_dat = '0;
    item.rsp_err = 1'b0;
    start_item(item);
    finish_item(item);
    // item.adr/dat/we now contain request[0]

    // ----------------------------------------------------------------
    // Iterations 1..n_ops-1: send previous response, get next request.
    // ----------------------------------------------------------------
    for (int i = 0; i < n_ops - 1; i++) begin
      fwvip_wb_seq_item next_item;
      bit do_err;

      // Service request[i]
      do_err = should_error(item.adr[31:0], item.we);
      if (item.we && !do_err)
        mem_model[item.adr[31:0]] = item.dat[31:0];

      // Build response for request[i]
      next_item         = fwvip_wb_seq_item::type_id::create("item");
      next_item.rsp_dat = do_err ? '0 :
                          (item.we ? '0 :
                          (mem_model.exists(item.adr[31:0]) ?
                           {32'b0, mem_model[item.adr[31:0]]} : '0));
      next_item.rsp_err = do_err;

      start_item(next_item);
      finish_item(next_item);  // driver: rsp_put(prev), req_get → next req
      item = next_item;
    end

    // ----------------------------------------------------------------
    // Final item: service last request and send its response.
    // Driver will rsp_put then block on req_get (killed at test end).
    // ----------------------------------------------------------------
    begin
      bit do_err;
      fwvip_wb_seq_item final_item;
      do_err = should_error(item.adr[31:0], item.we);
      if (item.we && !do_err)
        mem_model[item.adr[31:0]] = item.dat[31:0];

      final_item = fwvip_wb_seq_item::type_id::create("final");
      final_item.rsp_dat = do_err ? '0 :
                           (item.we ? '0 :
                           (mem_model.exists(item.adr[31:0]) ?
                            {32'b0, mem_model[item.adr[31:0]]} : '0));
      final_item.rsp_err = do_err;
      start_item(final_item);
      finish_item(final_item);  // driver: rsp_put(final), blocks on req_get
    end
  endtask

endclass
