// Operation API for the target agent (reactive / handler-sequence mode).
// The driver polls for bus requests via req_get() and returns responses
// via rsp_put().  Separating the two calls lets the handler sequence
// inspect the request before computing the response.
interface class fwvip_wb_targ_op_api;
  // Block until the reactive core reports an observed bus request.
  pure virtual task req_get(
    output bit [FWVIP_WB_ADDR_WIDTH_MAX-1:0] adr,
    output bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] dat,
    output bit                               we
  );
  // Inject a response; the core will drive ack/dat_r when it arrives.
  pure virtual task rsp_put(
    input  bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] rsp_dat,
    input  bit                               rsp_err
  );
endclass
