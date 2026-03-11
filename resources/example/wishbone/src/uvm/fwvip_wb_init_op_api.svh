// Operation API for the initiator agent.
// Declared as an interface class so fwvip_wb_init_cfg can extend uvm_object
// while still exposing the typed operation API to drivers.
interface class fwvip_wb_init_op_api;
  pure virtual task do_req(
    input  bit [FWVIP_WB_ADDR_WIDTH_MAX-1:0] adr,
    input  bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] dat,
    input  bit                               we,
    output bit [FWVIP_WB_DATA_WIDTH_MAX-1:0] rsp_dat,
    output bit                               rsp_err
  );
endclass
