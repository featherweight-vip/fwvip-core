
/**
 * ingress_fifo_tb — simulation testbench for fwvip_sv_ingress_fifo
 *
 * Tests:
 *   1. Basic push/pop: 4 items through a DEPTH=4 FIFO
 *   2. Full-FIFO blocking: producer put() stalls when FIFO is full
 *   3. Concurrent push/pop: consumer pops while producer pushes
 *   4. Ordering: items must arrive in FIFO order
 */
module ingress_fifo_tb;

    localparam int WIDTH         = 32;
    localparam int DEPTH         = 4;
    localparam int TIMEOUT_CYCLES = 10_000;

    // -------------------------------------------------------------------
    // Clock and reset
    // -------------------------------------------------------------------
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
        repeat (4) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
    end

    // -------------------------------------------------------------------
    // Timeout watchdog
    // -------------------------------------------------------------------
    int unsigned cycle_count = 0;
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (cycle_count >= TIMEOUT_CYCLES) begin
            $display("ERROR [%0t]: testbench timeout after %0d cycles",
                     $time, TIMEOUT_CYCLES);
            $finish(1);
        end
    end

    // -------------------------------------------------------------------
    // DUT: FIFO interface instance
    // -------------------------------------------------------------------
    logic                fifo_valid;
    logic [WIDTH-1:0]    fifo_data;
    logic                fifo_ready;

    fwvip_sv_ingress_fifo #(
        .WIDTH (WIDTH),
        .DEPTH (DEPTH)
    ) u_fifo (
        .clock (clk),
        .reset (reset),
        .valid (fifo_valid),
        .data  (fifo_data),
        .ready (fifo_ready)
    );

    // -------------------------------------------------------------------
    // Consumer: task to pop one item (blocks until valid)
    // -------------------------------------------------------------------
    task automatic pop_one(output logic [WIDTH-1:0] item);
        // Wait for something to be available
        @(posedge clk);
        while (!fifo_valid) @(posedge clk);
        item       = fifo_data;
        fifo_ready = 1'b1;
        @(posedge clk);
        fifo_ready = 1'b0;
    endtask

    // -------------------------------------------------------------------
    // Checker helper
    // -------------------------------------------------------------------
    int fail_count = 0;

    task automatic check(
        input string       tag,
        input logic [31:0] got,
        input logic [31:0] exp
    );
        if (got !== exp) begin
            $display("FAIL [%s]: got 0x%08h, expected 0x%08h", tag, got, exp);
            fail_count++;
        end else
            $display("PASS [%s]: 0x%08h", tag, got);
    endtask

    // -------------------------------------------------------------------
    // Test body
    // -------------------------------------------------------------------
    initial begin
        logic [WIDTH-1:0] item;

        fifo_ready = 1'b0;

        while (reset) @(posedge clk);
        repeat (2) @(posedge clk);

        // ---------------------------------------------------------------
        // Test 1: Fill FIFO to capacity without any consumer activity.
        //         All four put() calls should complete because DEPTH=4.
        // ---------------------------------------------------------------
        $display("[ingress_fifo_tb] --- Test 1: fill FIFO ---");
        fork
            begin
                u_fifo.put(32'hAAAA_0001);
                u_fifo.put(32'hAAAA_0002);
                u_fifo.put(32'hAAAA_0003);
                u_fifo.put(32'hAAAA_0004);
                $display("[ingress_fifo_tb]   producer: all 4 items pushed");
            end
        join
        // All items should now be in the FIFO (valid=1)
        @(posedge clk);
        if (!fifo_valid)
            $display("FAIL [t1]: FIFO should be non-empty after push");
        else
            $display("PASS [t1]: FIFO valid after fill");

        // ---------------------------------------------------------------
        // Test 2: Drain the FIFO and verify order.
        // ---------------------------------------------------------------
        $display("[ingress_fifo_tb] --- Test 2: drain and check order ---");
        pop_one(item); check("t2[0]", item, 32'hAAAA_0001);
        pop_one(item); check("t2[1]", item, 32'hAAAA_0002);
        pop_one(item); check("t2[2]", item, 32'hAAAA_0003);
        pop_one(item); check("t2[3]", item, 32'hAAAA_0004);

        @(posedge clk);
        if (fifo_valid)
            $display("FAIL [t2]: FIFO should be empty after drain");
        else
            $display("PASS [t2]: FIFO empty after drain");

        // ---------------------------------------------------------------
        // Test 3: Blocking behavior — producer pushes 8 items (2× DEPTH)
        //         while the consumer pops them one by one.
        // ---------------------------------------------------------------
        $display("[ingress_fifo_tb] --- Test 3: producer blocks on full FIFO ---");
        fork
            // Producer: 8 items
            begin : producer
                for (int i = 1; i <= 8; i++) begin
                    u_fifo.put(32'hBBBB_0000 | i);
                end
                $display("[ingress_fifo_tb]   producer done (8 items)");
            end

            // Consumer: wait 6 cycles (let FIFO fill up), then drain
            begin : consumer
                repeat (6) @(posedge clk);
                for (int i = 1; i <= 8; i++) begin
                    pop_one(item);
                    check($sformatf("t3[%0d]", i), item, 32'hBBBB_0000 | i);
                end
                $display("[ingress_fifo_tb]   consumer done (8 items)");
            end
        join

        // ---------------------------------------------------------------
        // Test 4: Single-item FIFO behaviour (push then immediate pop).
        // ---------------------------------------------------------------
        $display("[ingress_fifo_tb] --- Test 4: interleaved single push/pop ---");
        fork
            begin
                u_fifo.put(32'hCCCC_0001);
                u_fifo.put(32'hCCCC_0002);
                u_fifo.put(32'hCCCC_0003);
            end
            begin
                // Start popping one cycle after the first push completes
                repeat (2) @(posedge clk);
                pop_one(item); check("t4[0]", item, 32'hCCCC_0001);
                pop_one(item); check("t4[1]", item, 32'hCCCC_0002);
                pop_one(item); check("t4[2]", item, 32'hCCCC_0003);
            end
        join

        // ---------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------
        repeat (4) @(posedge clk);
        if (fail_count == 0)
            $display("[ingress_fifo_tb] ALL TESTS PASSED");
        else
            $display("[ingress_fifo_tb] %0d TEST(S) FAILED", fail_count);

        $finish;
    end

endmodule
