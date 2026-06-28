class fwvip_wb_seq_item extends uvm_sequence_item;
  `uvm_object_utils(fwvip_wb_seq_item)

  rand bit [FWVIP_WB_ADDR_WIDTH_MAX-1:0] adr;
  rand bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] dat;
  rand bit                               we;

  // Populated by the driver after the transaction completes
  bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] rsp_dat;
  bit                               rsp_err;

  // Actual widths — set by agent from cfg before randomisation
  int unsigned addr_width = FWVIP_WB_ADDR_WIDTH_MAX;
  int unsigned data_width = FWVIP_WB_DATA_WIDTH_MAX;

  constraint c_adr_width { adr < (1 << addr_width); }
  constraint c_dat_width { dat < (1 << data_width); }

  function new(string name = "fwvip_wb_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("adr=0x%08h dat=0x%08h we=%0b rsp_dat=0x%08h rsp_err=%0b",
                     adr, dat, we, rsp_dat, rsp_err);
  endfunction

endclass
