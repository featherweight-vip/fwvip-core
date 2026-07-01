/**
 * clkrst_uvm_tb -- top-level TB for the core clock/reset UVM configs.
 *
 * Drives a free-running clock and a finite reset, binds the signal-level
 * clock/reset transactor interfaces to them, wraps each in its config object,
 * and publishes the configs into the UVM config DB for the test hierarchy.
 */
`include "uvm_macros.svh"

module clkrst_uvm_tb;
    import uvm_pkg::*;
    import fwvip_core_uvm_pkg::*;
    import fwvip_core_clkrst_tests_pkg::*;

    localparam int RESET_CYCLES = 5;

    // ------------------------------------------------------------------
    // Clock / reset (10ns period; reset held 5 posedges)
    // ------------------------------------------------------------------
    logic clk;
    logic reset;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        `ifdef DEBUG
        $dumpfile("trace.fst");
        $dumpvars;
        `endif
        reset = 1'b1;
        repeat (RESET_CYCLES) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
    end

    // ------------------------------------------------------------------
    // Signal-level transactor interfaces
    // ------------------------------------------------------------------
    fwvip_clock_xtor_if u_clk_if (
        .clock (clk),
        .reset (reset)
    );

    fwvip_reset_xtor_if #(.ACTIVE(1)) u_rst_if (
        .clock (clk),
        .reset (reset)
    );

    // ------------------------------------------------------------------
    // Wrap each transactor in its config object and publish to the DB.
    // The whole test subtree ("*") shares the single clock & reset config.
    // ------------------------------------------------------------------
    initial begin
        fwvip_clock_config_p #(virtual fwvip_clock_xtor_if)::set(
            null, "*", "clock", u_clk_if);
        fwvip_reset_config_p #(virtual fwvip_reset_xtor_if #(1))::set(
            null, "*", "reset", u_rst_if);

        run_test("fwvip_core_clkrst_test");
    end

endmodule
