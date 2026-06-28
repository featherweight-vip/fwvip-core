/**
 * fwvip_wb_target_sv — SV wrapper for the Wishbone target BFM.
 *
 * When REACTIVE=0 (default) the core uses its internal memory model.
 * When REACTIVE=1 the core operates in handler-sequence mode: it pushes
 * observed bus requests to bfm_if.req_fifo and waits for responses
 * injected via bfm_if.rsp_fifo.  Use with the fwvip_wb_targ_agent.
 */
`include "fwvip_wb_macros.svh"

module fwvip_wb_target_sv #(
        parameter int  ADDR_WIDTH = 32,
        parameter int  DATA_WIDTH = 32,
        parameter int  MEM_SIZE   = 256,
        parameter bit  REACTIVE   = 1'b0,
        parameter int  _REQ_WIDTH = `FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH),
        parameter int  _RSP_WIDTH = `FWVIP_WB_RSP_WIDTH(ADDR_WIDTH, DATA_WIDTH)
    ) (
        input                           clock,
        input                           reset,

        // Wishbone B.3 target signals
        input  [ADDR_WIDTH-1:0]         adr,
        input                           cyc,
        input                           stb,
        input                           we,
        output                          ack,
        output                          err,
        input  [(DATA_WIDTH/8)-1:0]     sel,
        input  [DATA_WIDTH-1:0]         dat_w,
        output [DATA_WIDTH-1:0]         dat_r
    );

    // Aggregating interface with inline FIFO logic and req_get/rsp_put tasks.
    fwvip_wb_target_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) bfm_if (
        .clock (clock),
        .reset (reset)
    );

    // Core BFM: connected to bfm_if wires.
    fwvip_wb_target_core #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .MEM_SIZE   (MEM_SIZE),
        .REACTIVE   (REACTIVE)
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
