/**
 * fwvip_wb_monitor_if — Monitor BFM interface.
 *
 * Delegates transaction capture to fwvip_sv_egress_fifo.  The parent
 * module connects the ready/valid wires to the fwvip_wb_monitor_core.
 *
 * Testbench usage (direct hierarchical reference):
 *   tb.u_monitor.bfm_if.get(obs);   // blocking receive of next transaction
 */
`include "fwvip_wb_macros.svh"

interface fwvip_wb_monitor_if #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int _MON_WIDTH = `FWVIP_WB_MON_WIDTH(ADDR_WIDTH, DATA_WIDTH)
    ) (
        input clock,
        input reset
    );

    // ----------------------------------------------------------------
    // Wires the parent module connects to the core BFM ports.
    // ----------------------------------------------------------------
    wire                    mon_valid;
    wire [_MON_WIDTH-1:0]   mon_data;
    wire                    mon_ready;

    // ----------------------------------------------------------------
    // Monitor egress FIFO: core → mon_valid/mon_data → get() task
    // ----------------------------------------------------------------
    fwvip_sv_egress_fifo #(
        .WIDTH (_MON_WIDTH)
    ) mon_fifo (
        .clock (clock),
        .reset (reset),
        .valid (mon_valid),
        .data  (mon_data),
        .ready (mon_ready)
    );

    task get(output bit [_MON_WIDTH-1:0] data);
        mon_fifo.get(data);
    endtask

endinterface
