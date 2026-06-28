/**
 * fwvip_wb_target_if — Target BFM interface.
 *
 * In REACTIVE mode (used by the UVM target agent) the signal directions are:
 *   req_valid/req_data — driven by the core when it observes a bus request
 *   req_ready          — driven by the egress FIFO (space available)
 *   rsp_valid/rsp_data — driven by the ingress FIFO (TB-injected response)
 *   rsp_ready          — driven by the core when it consumes a response
 *
 * UVM agent usage:
 *   vif.req_get(raw);   // blocking: wait for an observed bus request
 *   vif.rsp_put(raw);   // blocking: inject a response for the core to drive
 */
`include "fwvip_wb_macros.svh"

interface fwvip_wb_target_if #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int _REQ_WIDTH = `FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH),
        parameter int _RSP_WIDTH = `FWVIP_WB_RSP_WIDTH(ADDR_WIDTH, DATA_WIDTH)
    ) (
        input clock,
        input reset
    );

    // ----------------------------------------------------------------
    // Wires connecting the core BFM ports to the FIFO primitives.
    // req_*: core drives valid/data; egress FIFO drives ready.
    // rsp_*: ingress FIFO drives valid/data; core drives ready.
    // ----------------------------------------------------------------
    wire                    req_valid;
    wire [_REQ_WIDTH-1:0]   req_data;
    wire                    req_ready;

    wire                    rsp_valid;
    wire [_RSP_WIDTH-1:0]   rsp_data;
    wire                    rsp_ready;

    // ----------------------------------------------------------------
    // Observed-request egress FIFO: core → req_valid/req_data → get()
    // ----------------------------------------------------------------
    fwvip_sv_egress_fifo #(
        .WIDTH (_REQ_WIDTH)
    ) req_fifo (
        .clock (clock),
        .reset (reset),
        .valid (req_valid),
        .data  (req_data),
        .ready (req_ready)
    );

    // ----------------------------------------------------------------
    // Injected-response ingress FIFO: put() → rsp_valid/rsp_data → core
    // ----------------------------------------------------------------
    fwvip_sv_ingress_fifo #(
        .WIDTH (_RSP_WIDTH)
    ) rsp_fifo (
        .clock (clock),
        .reset (reset),
        .valid (rsp_valid),
        .data  (rsp_data),
        .ready (rsp_ready)
    );

    // Wait for an observed bus request pushed by the reactive core.
    task req_get(output bit [_REQ_WIDTH-1:0] data);
        req_fifo.get(data);
    endtask

    // Inject a response; the reactive core drives ack/dat_r when it arrives.
    task rsp_put(input bit [_RSP_WIDTH-1:0] data);
        rsp_fifo.put(data);
    endtask

endinterface
