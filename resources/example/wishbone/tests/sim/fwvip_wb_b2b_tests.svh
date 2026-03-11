// Test 1: directed write-read.
// Writes 4 fixed values, reads them back, checks data matches.
// Also verifies the monitor observed exactly 8 transactions.
class fwvip_wb_b2b_directed_test extends uvm_test;
  `uvm_component_utils(fwvip_wb_b2b_directed_test)

  fwvip_wb_b2b_env env;
  uvm_tlm_analysis_fifo #(fwvip_wb_mon_item) mon_fifo;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    env      = fwvip_wb_b2b_env::type_id::create("env", this);
    mon_fifo = new("mon_fifo", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    env.mon_agent.ap.connect(mon_fifo.analysis_export);
  endfunction

  task run_phase(uvm_phase phase);
    fwvip_wb_write_seq wr_seq;
    fwvip_wb_read_seq  rd_seq;
    fwvip_wb_mon_item  mon_item;
    int fail_count = 0;
    int mon_count  = 0;

    bit [31:0] addrs[4] = '{32'h00, 32'h04, 32'h08, 32'h0C};
    bit [31:0] wdata[4] = '{32'hDEAD_BEEF, 32'hCAFE_BABE,
                             32'h1234_5678, 32'h9ABC_DEF0};

    phase.raise_objection(this);

    // Write phase
    wr_seq       = fwvip_wb_write_seq::type_id::create("wr_seq");
    wr_seq.addrs = addrs;
    wr_seq.data  = wdata;
    wr_seq.start(env.init_agent.seqr);

    // Read phase
    rd_seq       = fwvip_wb_read_seq::type_id::create("rd_seq");
    rd_seq.addrs = addrs;
    rd_seq.start(env.init_agent.seqr);

    // Check returned data
    foreach (addrs[i]) begin
      if (rd_seq.read_data[i] !== wdata[i]) begin
        `uvm_error("DATA_MISMATCH",
            $sformatf("addr=0x%08h: got 0x%08h, exp 0x%08h",
                      addrs[i], rd_seq.read_data[i], wdata[i]))
        fail_count++;
      end
    end

    // Drain monitor FIFO; allow a few cycles for last transaction to arrive
    repeat (8) @(posedge $root.b2b_uvm_tb.clk);
    while (mon_fifo.try_get(mon_item)) begin
      `uvm_info("MON", mon_item.convert2string(), UVM_HIGH)
      mon_count++;
    end
    if (mon_count !== 8)
      `uvm_error("MON_COUNT",
          $sformatf("Expected 8 monitor items, got %0d", mon_count))

    if (fail_count == 0 && mon_count == 8)
      `uvm_info("TEST", "fwvip_wb_b2b_directed_test PASSED", UVM_LOW)

    phase.drop_objection(this);
  endtask

endclass

// Test 2: randomised write-read.
// Randomises n_ops (4-16) writes, reads back all written addresses, verifies.
// Monitor should see exactly 2*n_ops transactions.
class fwvip_wb_b2b_rand_test extends uvm_test;
  `uvm_component_utils(fwvip_wb_b2b_rand_test)

  fwvip_wb_b2b_env env;
  uvm_tlm_analysis_fifo #(fwvip_wb_mon_item) mon_fifo;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    env      = fwvip_wb_b2b_env::type_id::create("env", this);
    mon_fifo = new("mon_fifo", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    env.mon_agent.ap.connect(mon_fifo.analysis_export);
  endfunction

  task run_phase(uvm_phase phase);
    fwvip_wb_write_seq   wr_seq;
    fwvip_wb_read_seq    rd_seq;
    fwvip_wb_mon_item    mon_item;
    int fail_count = 0;
    int mon_count  = 0;
    localparam int N_OPS = 8;

    phase.raise_objection(this);

    // Write phase: 8 sequential word-aligned addresses with fixed data pattern
    wr_seq        = fwvip_wb_write_seq::type_id::create("wr_seq");
    wr_seq.addrs  = new[N_OPS];
    wr_seq.data   = new[N_OPS];
    for (int i = 0; i < N_OPS; i++) begin
      wr_seq.addrs[i] = i * 4;
      wr_seq.data[i]  = 32'hDEAD_0000 | i;
    end
    wr_seq.start(env.init_agent.seqr);

    // Read back the written addresses
    rd_seq       = fwvip_wb_read_seq::type_id::create("rd_seq");
    rd_seq.addrs = wr_seq.addrs;
    rd_seq.start(env.init_agent.seqr);

    // Verify returned data
    for (int i = 0; i < N_OPS; i++) begin
      if (rd_seq.read_data[i] !== wr_seq.data[i]) begin
        `uvm_error("DATA_MISMATCH",
            $sformatf("addr=0x%08h: got 0x%08h, exp 0x%08h",
                      wr_seq.addrs[i], rd_seq.read_data[i], wr_seq.data[i]))
        fail_count++;
      end
    end

    // Drain monitor FIFO
    repeat (8) @(posedge $root.b2b_uvm_tb.clk);
    while (mon_fifo.try_get(mon_item)) begin
      `uvm_info("MON", mon_item.convert2string(), UVM_HIGH)
      mon_count++;
    end
    if (mon_count !== 2 * N_OPS)
      `uvm_error("MON_COUNT",
          $sformatf("Expected %0d monitor items, got %0d",
                    2 * N_OPS, mon_count))

    if (fail_count == 0 && mon_count == 2 * N_OPS)
      `uvm_info("TEST", "fwvip_wb_b2b_rand_test PASSED", UVM_LOW)

    phase.drop_objection(this);
  endtask

endclass
