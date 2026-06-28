// Parameterised config extension for the target agent.
// Holds the virtual interface handle and implements req_get()/rsp_put()
// by calling the reactive BFM's FIFO tasks.
class fwvip_wb_targ_cfg_t #(
  int ADDR_WIDTH = 32,
  int DATA_WIDTH = 32
) extends fwvip_wb_targ_cfg;

  virtual fwvip_wb_target_if #(ADDR_WIDTH, DATA_WIDTH) vif;

  function new(string name = "fwvip_wb_targ_cfg_t");
    super.new(name);
    addr_width = ADDR_WIDTH;
    data_width = DATA_WIDTH;
  endfunction

  // Block until the reactive core reports an observed bus request.
  virtual task req_get(
    output bit [FWVIP_WB_ADDR_WIDTH_MAX-1:0] adr,
    output bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] dat,
    output bit                               we
  );
    `FWVIP_WB_REQ_STRUCT(ADDR_WIDTH, DATA_WIDTH) req_s;
    bit [`FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH)-1:0] raw;

    vif.req_get(raw);
    req_s = raw;
    adr = {{(FWVIP_WB_ADDR_WIDTH_MAX-ADDR_WIDTH){1'b0}}, req_s.adr};
    dat = {{(FWVIP_WB_DATA_WIDTH_MAX-DATA_WIDTH){1'b0}}, req_s.dat};
    we  = req_s.we;
  endtask

  // Inject a response; the reactive core drives ack/dat_r when it arrives.
  virtual task rsp_put(
    input  bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] rsp_dat,
    input  bit                               rsp_err
  );
    `FWVIP_WB_RSP_STRUCT(ADDR_WIDTH, DATA_WIDTH) rsp_s;
    rsp_s.dat = rsp_dat[DATA_WIDTH-1:0];
    rsp_s.err = rsp_err;
    vif.rsp_put(`FWVIP_WB_RSP_WIDTH(ADDR_WIDTH, DATA_WIDTH)'(rsp_s));
  endtask

endclass
