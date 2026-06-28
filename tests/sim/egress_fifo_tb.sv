/**
 * egress_fifo_tb — simulation testbench for fwvip_sv_egress_fifo
 *
 * Tests:
 *   1. Basic push/pop: 4 items through a DEPTH=4 FIFO
 *   2. Drain and check order: verify FIFO ordering
 *   3. Consumer waits for producer: get() blocks until data arrives
 *   4. Interleaved single push/pop
 */
module egress_fifo_tb;

    localparam int WIDTH          = 32;
    localparam int DEPTH          = 4;
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
    // DUT: Egress FIFO interface instance
    // -------------------------------------------------------------------
    logic             src_valid;
    logic [WIDTH-1:0] src_data;
    logic             src_ready;

    fwvip_sv_egress_fifo #(
        .WIDTH (WIDTH),
        .DEPTH (DEPTH)
    ) u_fifo (
        .clock (clk),
        .reset (reset),
        .valid (src_valid),
        .data  (src_data),
        .ready (src_ready)
    );

    // -------------------------------------------------------------------
    // Source: task to push one item (waits until FIFO has space)
    //
    // After @(posedge clk), src_ready reflects (count < DEPTH) with the
    // updated count.  Because count only changes at posedge, src_ready is
    // stable between edges, so asserting valid one cycle after checking
    // ready guarantees the transfer is accepted at the following posedge.
    // -------------------------------------------------------------------
    task automatic push_one(input logic [WIDTH-1:0] item);
        @(posedge clk);
        while (!src_ready) @(posedge clk);
        src_data  = item;
        src_valid = 1'b1;
        @(posedge clk);
        src_valid = 1'b0;
        src_data  = '0;
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

        src_valid = 1'b0;
        src_data  = '0;

        while (reset) @(posedge clk);
        repeat (2) @(posedge clk);

        // ---------------------------------------------------------------
        // Test 1: Push 4 items from the source into a DEPTH=4 FIFO.
        //         All push_one() calls should complete without blocking.
        // ---------------------------------------------------------------
        $display("[egress_fifo_tb] --- Test 1: fill FIFO ---");
        fork
            begin
                push_one(32'hAAAA_0001);
                push_one(32'hAAAA_0002);
                push_one(32'hAAAA_0003);
                push_one(32'hAAAA_0004);
                $display("[egress_fifo_tb]   source: all 4 items sent");
            end
        join

        // ---------------------------------------------------------------
        // Test 2: Drain the FIFO via get() and verify ordering.
        // ---------------------------------------------------------------
        $display("[egress_fifo_tb] --- Test 2: drain and check order ---");
        u_fifo.get(item); check("t2[0]", item, 32'hAAAA_0001);
        u_fifo.get(item); check("t2[1]", item, 32'hAAAA_0002);
        u_fifo.get(item); check("t2[2]", item, 32'hAAAA_0003);
        u_fifo.get(item); check("t2[3]", item, 32'hAAAA_0004);

        // ---------------------------------------------------------------
        // Test 3: Consumer waits for producer — get() is called first,
        //         producer starts 6 cycles later.  get() must block until
        //         data arrives and each item must be correct.
        // ---------------------------------------------------------------
        $display("[egress_fifo_tb] --- Test 3: consumer waits for data ---");
        fork
            begin : consumer
                for (int i = 1; i <= 8; i++) begin
                    u_fifo.get(item);
                    check($sformatf("t3[%0d]", i), item, 32'hBBBB_0000 | i);
                end
                $display("[egress_fifo_tb]   consumer done (8 items)");
            end

            begin : producer
                repeat (6) @(posedge clk);
                for (int i = 1; i <= 8; i++) begin
                    push_one(32'hBBBB_0000 | i);
                end
                $display("[egress_fifo_tb]   source done (8 items)");
            end
        join

        // ---------------------------------------------------------------
        // Test 4: Interleaved single push/pop — producer pushes 3 items
        //         while consumer pops them concurrently.
        // ---------------------------------------------------------------
        $display("[egress_fifo_tb] --- Test 4: interleaved single push/pop ---");
        fork
            begin
                push_one(32'hCCCC_0001);
                push_one(32'hCCCC_0002);
                push_one(32'hCCCC_0003);
            end
            begin
                repeat (2) @(posedge clk);
                u_fifo.get(item); check("t4[0]", item, 32'hCCCC_0001);
                u_fifo.get(item); check("t4[1]", item, 32'hCCCC_0002);
                u_fifo.get(item); check("t4[2]", item, 32'hCCCC_0003);
            end
        join

        // ---------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------
        repeat (4) @(posedge clk);
        if (fail_count == 0)
            $display("[egress_fifo_tb] ALL TESTS PASSED");
        else
            $display("[egress_fifo_tb] %0d TEST(S) FAILED", fail_count);

        $finish;
    end

endmodule
