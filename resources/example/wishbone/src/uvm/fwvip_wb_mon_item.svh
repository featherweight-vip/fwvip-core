class fwvip_wb_mon_item extends uvm_sequence_item;
  `uvm_object_utils(fwvip_wb_mon_item)

  bit [FWVIP_WB_ADDR_WIDTH_MAX-1:0] adr;
  bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] dat;
  bit                               err;
  bit                               we;
  bit [15:0]                        cyc_len;

  function new(string name = "fwvip_wb_mon_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("adr=0x%08h dat=0x%08h we=%0b err=%0b cyc_len=%0d",
                     adr, dat, we, err, cyc_len);
  endfunction

endclass
