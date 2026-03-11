// Reactive target back-to-back test.
//
// The initiator writes 4 word-aligned addresses then reads them back.
// The target handler sequence services each transaction using its own
// memory model.  The test verifies:
//   1. Read-back data matches written data.
//   2. The monitor observed exactly 8 transactions (4 writes + 4 reads).
class fwvip_wb_b2b_targ_test extends uvm_test;
  `uvm_component_utils(fwvip_wb_b2b_targ_test)

  fwvip_wb_b2b_targ_env env;
  uvm_tlm_analysis_fifo #(fwvip_wb_mon_item) mon_fifo;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    env      = fwvip_wb_b2b_targ_env::type_id::create("env", this);
    mon_fifo = new("mon_fifo", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    env.mon_agent.ap.connect(mon_fifo.analysis_export);
  endfunction

  task run_phase(uvm_phase phase);
    fwvip_wb_write_seq          wr_seq;
    fwvip_wb_read_seq           rd_seq;
    fwvip_wb_targ_handler_seq   handler_seq;
    fwvip_wb_mon_item           mon_item;
    int fail_count = 0;
    int mon_count  = 0;
    localparam int N_OPS = 4;

    phase.raise_objection(this);

    // Launch handler sequence on targ_agent in background; run initiator
    // traffic sequentially in the main thread.  join_none avoids a Verilator
    // scheduling deadlock that occurs when two blocking seq.start() calls run
    // in concurrent fork branches.
    handler_seq        = fwvip_wb_targ_handler_seq::type_id::create("handler_seq");
    handler_seq.n_ops  = N_OPS * 2;  // 4 writes + 4 reads
    fork
      handler_seq.start(env.targ_agent.seqr);
    join_none

    // Yield once so the handler seq can register with targ_seqr before the
    // first initiator transaction arrives.
    #0;

    begin
        // Write phase
        wr_seq       = fwvip_wb_write_seq::type_id::create("wr_seq");
        wr_seq.addrs = new[N_OPS];
        wr_seq.data  = new[N_OPS];
        for (int i = 0; i < N_OPS; i++) begin
          wr_seq.addrs[i] = i * 4;
          wr_seq.data[i]  = 32'hCAFE_0000 | i;
        end
        wr_seq.start(env.init_agent.seqr);

        // Read phase
        rd_seq       = fwvip_wb_read_seq::type_id::create("rd_seq");
        rd_seq.addrs = wr_seq.addrs;
        rd_seq.start(env.init_agent.seqr);
    end

    // Verify read-back data
    for (int i = 0; i < N_OPS; i++) begin
      if (rd_seq.read_data[i] !== wr_seq.data[i]) begin
        `uvm_error("DATA_MISMATCH",
            $sformatf("addr=0x%08h: got 0x%08h, exp 0x%08h",
                      wr_seq.addrs[i], rd_seq.read_data[i], wr_seq.data[i]))
        fail_count++;
      end
    end

    // Drain and count monitor items
    repeat (8) @(posedge $root.b2b_targ_uvm_tb.clk);
    while (mon_fifo.try_get(mon_item)) begin
      `uvm_info("MON", mon_item.convert2string(), UVM_HIGH)
      mon_count++;
    end
    if (mon_count !== 2 * N_OPS)
      `uvm_error("MON_COUNT",
          $sformatf("Expected %0d monitor items, got %0d", 2 * N_OPS, mon_count))

    if (fail_count == 0 && mon_count == 2 * N_OPS)
      `uvm_info("TEST", "fwvip_wb_b2b_targ_test PASSED", UVM_LOW)

    phase.drop_objection(this);
  endtask

endclass
