`include "rv_macros.svh"
`include "fwvip_macros.svh"

/**
 * Egress FIFO BFM (consumer side)
 *
 * - Monitors a ready/valid/data channel (initiator drives dat/valid)
 * - get() blocks until a transfer occurs and returns the data item
 * - Provides backpressure by only asserting ready while get() is waiting
 */
interface fwvip_egress_fifo_if #(
        parameter int WIDTH = 32
    ) (
        input               clock,
        input               reset,
        // Target (consumer) port: we receive dat/valid and drive ready
        `RV_TARGET_PORT(e_, WIDTH)
    );

    // Internal ready driver
    logic ready_drv;
    assign e_ready = ready_drv;

    // Initialize
    initial begin
        ready_drv = 1'b1; // Always ready after time 0
    end


    // Debug: indicate interface is alive
    initial begin
        $warning("fwvip_egress_fifo_if alive");
    end

    /**
     * Blocking get: waits for a valid item to be transferred and returns it.
     * Asserts ready while waiting. Deasserts after the item is captured.
     */
    task automatic get(output reg [WIDTH-1:0] data);
        // Assert ready and wait until a valid is present (while out of reset)
        ready_drv = 1'b1;
        // Wait for reset deassertion if needed
        if (reset) @(negedge reset);
        // Wait for a clock edge where a handshake occurs
        do @(posedge clock); while (!(e_valid && e_ready));
        data = e_dat;
        // Deassert ready after capturing the item
        ready_drv = 1'b0;
    endtask

endinterface
