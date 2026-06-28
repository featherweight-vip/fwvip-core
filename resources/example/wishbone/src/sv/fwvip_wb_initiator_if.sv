/**
 * fwvip_wb_initiator_if — Initiator BFM interface.
 *
 * Delegates request/response FIFO management to fwvip_sv_ingress_fifo
 * and fwvip_sv_egress_fifo.  The parent module connects the ready/valid
 * wires to the fwvip_wb_initiator_core.
 *
 * Testbench usage (direct hierarchical reference):
 *   tb.u_initiator.bfm_if.req_put({addr, data, we});   // issue a request
 *   tb.u_initiator.bfm_if.rsp_get(rsp);                // collect a response
 */
`include "fwvip_wb_macros.svh"

interface fwvip_wb_initiator_if #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int _REQ_WIDTH = `FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH)
    ) (
        input clock,
        input reset
    );

    // ----------------------------------------------------------------
    // Wires the parent module connects to the core BFM ports.
    // ----------------------------------------------------------------
    wire                    req_valid;
    wire [_REQ_WIDTH-1:0]   req_data;
    wire                    req_ready;

    wire                    rsp_valid;
    wire [_REQ_WIDTH-1:0]   rsp_data;
    wire                    rsp_ready;

    // ----------------------------------------------------------------
    // Request ingress FIFO: put() task → req_valid/req_data → core
    // ----------------------------------------------------------------
    fwvip_sv_ingress_fifo #(
        .WIDTH (_REQ_WIDTH)
    ) req_fifo (
        .clock (clock),
        .reset (reset),
        .valid (req_valid),
        .data  (req_data),
        .ready (req_ready)
    );

    // ----------------------------------------------------------------
    // Response egress FIFO: core → rsp_valid/rsp_data → get() task
    // ----------------------------------------------------------------
    fwvip_sv_egress_fifo #(
        .WIDTH (_REQ_WIDTH)
    ) rsp_fifo (
        .clock (clock),
        .reset (reset),
        .valid (rsp_valid),
        .data  (rsp_data),
        .ready (rsp_ready)
    );

    task static req_put(bit [_REQ_WIDTH-1:0] data);
        req_fifo.put(data);
    endtask

    task static rsp_get(output bit [_REQ_WIDTH-1:0] data);
        rsp_fifo.get(data);
    endtask

endinterface
