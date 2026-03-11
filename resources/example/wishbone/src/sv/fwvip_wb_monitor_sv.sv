/**
 * fwvip_wb_monitor_sv — SV wrapper for the Wishbone monitor BFM.
 *
 * Passively observes a Wishbone B.3 bus.  The class-based testbench
 * obtains a single virtual handle to bfm_if and calls get():
 *
 *   virtual fwvip_wb_monitor_if #() vif = tb.u_monitor.bfm_if;
 *   vif.get(obs);   // { adr, dat, err, we, cyc_len }
 */
`include "fwvip_wb_macros.svh"

module fwvip_wb_monitor_sv #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int _MON_WIDTH = `FWVIP_WB_MON_WIDTH(ADDR_WIDTH, DATA_WIDTH)
    ) (
        input                           clock,
        input                           reset,

        // Wishbone B.3 bus — all inputs (passive observation only)
        input  [ADDR_WIDTH-1:0]         adr,
        input                           cyc,
        input                           stb,
        input                           we,
        input                           ack,
        input                           err,
        input  [(DATA_WIDTH/8)-1:0]     sel,
        input  [DATA_WIDTH-1:0]         dat_w,
        input  [DATA_WIDTH-1:0]         dat_r
    );

    // Aggregating interface with inline FIFO logic and get() task.
    fwvip_wb_monitor_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) bfm_if (
        .clock (clock),
        .reset (reset)
    );

    // Core BFM: detects transactions and drives bfm_if wires.
    fwvip_wb_monitor_core #(
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
        .mon_valid (bfm_if.mon_valid),
        .mon_data  (bfm_if.mon_data),
        .mon_ready (bfm_if.mon_ready)
    );

endmodule
