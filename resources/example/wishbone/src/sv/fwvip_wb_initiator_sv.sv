/**
 * fwvip_wb_initiator_sv — SV wrapper for the Wishbone initiator BFM.
 *
 * Exposes Wishbone B.3 signals on the module boundary (driven by
 * fwvip_wb_initiator_core).  The class-based testbench obtains a single
 * virtual handle to bfm_if and calls its tasks:
 *
 *   virtual fwvip_wb_initiator_if #() vif = tb.u_initiator.bfm_if;
 *   vif.req_put({addr, data, we});   // issue a request
 *   vif.rsp_get(rsp);                // collect a response
 */
`include "fwvip_wb_macros.svh"

module fwvip_wb_initiator_sv #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int _REQ_WIDTH = `FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH),
        parameter int _RSP_WIDTH = `FWVIP_WB_RSP_WIDTH(ADDR_WIDTH, DATA_WIDTH)
    ) (
        input                           clock,
        input                           reset,

        // Wishbone B.3 initiator signals
        output [ADDR_WIDTH-1:0]         adr,
        output                          cyc,
        output                          stb,
        output                          we,
        input                           ack,
        input                           err,
        output [(DATA_WIDTH/8)-1:0]     sel,
        output [DATA_WIDTH-1:0]         dat_w,
        input  [DATA_WIDTH-1:0]         dat_r
    );

    // Aggregating interface with inline FIFO logic and put/get tasks.
    fwvip_wb_initiator_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) bfm_if (
        .clock (clock),
        .reset (reset)
    );

    // Core BFM: drives Wishbone signals, connected to bfm_if wires.
    fwvip_wb_initiator_core #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) core (
        .clock     (clock),
        .reset     (reset),
        .adr       (adr),
        .cyc       (cyc),
        .stb       (stb),
        .we        (we),
        .ack       (ack),
        .err       (err),
        .sel       (sel),
        .dat_w     (dat_w),
        .dat_r     (dat_r),
        .req_valid (bfm_if.req_valid),
        .req_data  (bfm_if.req_data),
        .req_ready (bfm_if.req_ready),
        .rsp_valid (bfm_if.rsp_valid),
        .rsp_data  (bfm_if.rsp_data),
        .rsp_ready (bfm_if.rsp_ready)
    );

endmodule

