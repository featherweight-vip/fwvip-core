// Write a list of {adr, dat} pairs to the initiator.
class fwvip_wb_write_seq extends uvm_sequence #(fwvip_wb_seq_item);
  `uvm_object_utils(fwvip_wb_write_seq)

  bit [FWVIP_WB_ADDR_WIDTH_MAX-1:0] addrs[];
  bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] data[];

  function new(string name = "fwvip_wb_write_seq");
    super.new(name);
  endfunction

  task body();
    fwvip_wb_seq_item item;
    foreach (addrs[i]) begin
      item = fwvip_wb_seq_item::type_id::create("item");
      start_item(item);
      item.adr = addrs[i];
      item.dat = data[i];
      item.we  = 1'b1;
      finish_item(item);
    end
  endtask

endclass

// Read a list of addresses; returned data is in read_data[] after body().
class fwvip_wb_read_seq extends uvm_sequence #(fwvip_wb_seq_item);
  `uvm_object_utils(fwvip_wb_read_seq)

  bit [FWVIP_WB_ADDR_WIDTH_MAX-1:0] addrs[];
  bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] read_data[];  // output

  function new(string name = "fwvip_wb_read_seq");
    super.new(name);
  endfunction

  task body();
    fwvip_wb_seq_item item;
    read_data = new[addrs.size()];
    foreach (addrs[i]) begin
      item = fwvip_wb_seq_item::type_id::create("item");
      start_item(item);
      item.adr = addrs[i];
      item.we  = 1'b0;
      finish_item(item);
      read_data[i] = item.rsp_dat;
    end
  endtask

endclass

// Read a list of addresses and capture both returned data and error status.
class fwvip_wb_read_status_seq extends uvm_sequence #(fwvip_wb_seq_item);
  `uvm_object_utils(fwvip_wb_read_status_seq)

  bit [FWVIP_WB_ADDR_WIDTH_MAX-1:0] addrs[];
  bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] read_data[];
  bit                               read_err[];

  function new(string name = "fwvip_wb_read_status_seq");
    super.new(name);
  endfunction

  task body();
    fwvip_wb_seq_item item;
    read_data = new[addrs.size()];
    read_err  = new[addrs.size()];
    foreach (addrs[i]) begin
      item = fwvip_wb_seq_item::type_id::create("item");
      start_item(item);
      item.adr = addrs[i];
      item.we  = 1'b0;
      finish_item(item);
      read_data[i] = item.rsp_dat;
      read_err[i]  = item.rsp_err;
    end
  endtask

endclass

// Write n_ops items with sequential word-aligned addresses and randomised data.
// Captures written addresses and data for post-sequence verification.
class fwvip_wb_rand_wr_seq extends uvm_sequence #(fwvip_wb_seq_item);
  `uvm_object_utils(fwvip_wb_rand_wr_seq)

  rand int unsigned n_ops;
  constraint c_n_ops { n_ops inside {[4:16]}; }

  // Populated after body() completes
  bit [FWVIP_WB_ADDR_WIDTH_MAX-1:0] written_addrs[];
  bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] written_data[];

  function new(string name = "fwvip_wb_rand_wr_seq");
    super.new(name);
  endfunction

  task body();
    fwvip_wb_seq_item item;
    written_addrs = new[n_ops];
    written_data  = new[n_ops];
    for (int i = 0; i < int'(n_ops); i++) begin
      item = fwvip_wb_seq_item::type_id::create("item");
      start_item(item);
      // Randomise data; fix address to sequential word-aligned value
      // to guarantee unique addresses and avoid read-back aliasing.
      if (!item.randomize() with { item.we == 1'b1; })
        `uvm_fatal("RAND_FAIL", "randomize failed")
      item.adr = i * 4;
      finish_item(item);
      written_addrs[i] = item.adr;
      written_data[i]  = item.dat;
    end
  endtask

endclass
