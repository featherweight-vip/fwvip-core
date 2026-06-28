// Reactive target randomized back-to-back test.
//
// Uses the same target handler-sequence path as the directed test, but drives
// a longer stream of randomized writes before reading the same addresses back.
// This gives better confidence that the reactive FIFO path works beyond the
// minimal directed proof case.
class fwvip_wb_b2b_targ_rand_test extends uvm_test;
  `uvm_component_utils(fwvip_wb_b2b_targ_rand_test)

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
    fwvip_wb_rand_wr_seq        wr_seq;
    fwvip_wb_read_seq           rd_seq;
    fwvip_wb_targ_handler_seq   handler_seq;
    fwvip_wb_mon_item           mon_item;
    int fail_count = 0;
    int mon_count  = 0;
    localparam int N_OPS = 12;

    phase.raise_objection(this);

    handler_seq       = fwvip_wb_targ_handler_seq::type_id::create("handler_seq");
    handler_seq.n_ops = N_OPS * 2;
    fork
      handler_seq.start(env.targ_agent.seqr);
    join_none

    #0;

    wr_seq       = fwvip_wb_rand_wr_seq::type_id::create("wr_seq");
    wr_seq.n_ops = N_OPS;
    wr_seq.start(env.init_agent.seqr);

    rd_seq       = fwvip_wb_read_seq::type_id::create("rd_seq");
    rd_seq.addrs = wr_seq.written_addrs;
    rd_seq.start(env.init_agent.seqr);

    for (int i = 0; i < N_OPS; i++) begin
      if (rd_seq.read_data[i] !== wr_seq.written_data[i]) begin
        `uvm_error("DATA_MISMATCH",
            $sformatf("addr=0x%08h: got 0x%08h, exp 0x%08h",
                      wr_seq.written_addrs[i],
                      rd_seq.read_data[i],
                      wr_seq.written_data[i]))
        fail_count++;
      end
    end

    repeat (8) @(posedge $root.b2b_targ_uvm_tb.clk);
    while (mon_fifo.try_get(mon_item)) begin
      `uvm_info("MON", mon_item.convert2string(), UVM_HIGH)
      mon_count++;
    end
    if (mon_count !== 2 * N_OPS)
      `uvm_error("MON_COUNT",
          $sformatf("Expected %0d monitor items, got %0d", 2 * N_OPS, mon_count))

    if (fail_count == 0 && mon_count == 2 * N_OPS)
      `uvm_info("TEST", "fwvip_wb_b2b_targ_rand_test PASSED", UVM_LOW)

    phase.drop_objection(this);
  endtask

endclass
