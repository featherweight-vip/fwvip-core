// Parameterised config extension for the initiator agent.
// Holds the virtual interface handle and implements do_req() by packing
// the request struct, calling the BFM FIFO tasks, and unpacking the response.
class fwvip_wb_init_cfg_t #(
  int ADDR_WIDTH = 32,
  int DATA_WIDTH = 32
) extends fwvip_wb_init_cfg;

  virtual fwvip_wb_initiator_if #(ADDR_WIDTH, DATA_WIDTH) vif;

  function new(string name = "fwvip_wb_init_cfg_t");
    super.new(name);
    addr_width = ADDR_WIDTH;
    data_width = DATA_WIDTH;
  endfunction

  virtual task do_req(
    input  bit [FWVIP_WB_ADDR_WIDTH_MAX-1:0] adr,
    input  bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] dat,
    input  bit                               we,
    output bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] rsp_dat,
    output bit                               rsp_err
  );
    `FWVIP_WB_REQ_STRUCT(ADDR_WIDTH, DATA_WIDTH) req_s;
    `FWVIP_WB_RSP_STRUCT(ADDR_WIDTH, DATA_WIDTH) rsp_s;
    bit [`FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH)-1:0] rsp_raw;

    req_s.adr = adr[ADDR_WIDTH-1:0];
    req_s.dat = dat[DATA_WIDTH-1:0];
    req_s.we  = we;
    vif.req_put(`FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH)'(req_s));

    vif.rsp_get(rsp_raw);
    // RSP_STRUCT occupies the lower _RSP_WIDTH bits; upper bits are zero-padded
    rsp_s   = rsp_raw[`FWVIP_WB_RSP_WIDTH(ADDR_WIDTH, DATA_WIDTH)-1:0];
    rsp_dat = {{(FWVIP_WB_DATA_WIDTH_MAX-DATA_WIDTH){1'b0}}, rsp_s.dat};
    rsp_err = rsp_s.err;
  endtask

endclass
