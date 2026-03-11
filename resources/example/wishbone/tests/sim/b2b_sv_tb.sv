`include "fwvip_wb_macros.svh"

module b2b_sv_tb;

    // Parameters
    localparam int ADDR_WIDTH     = 32;
    localparam int DATA_WIDTH     = 32;
    localparam int SEL_WIDTH      = DATA_WIDTH / 8;
    localparam int REQ_WIDTH      = `FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH);  // 65
    localparam int MON_WIDTH      = `FWVIP_WB_MON_WIDTH(ADDR_WIDTH, DATA_WIDTH);  // 82
    localparam int TIMEOUT_CYCLES = 10_000;

    // ----------------------------------------------------------------
    // Clock / reset
    // ----------------------------------------------------------------
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
        repeat (8) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
    end

    int unsigned cycle_count = 0;
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (cycle_count >= TIMEOUT_CYCLES) begin
            $display("ERROR [%0t]: timeout after %0d cycles", $time, TIMEOUT_CYCLES);
            $finish(1);
        end
    end

    // ----------------------------------------------------------------
    // Wishbone bus
    // ----------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] wb_adr;
    logic                  wb_cyc;
    logic                  wb_stb;
    logic                  wb_we;
    logic                  wb_ack;
    logic                  wb_err;
    logic [SEL_WIDTH-1:0]  wb_sel;
    logic [DATA_WIDTH-1:0] wb_dat_w;
    logic [DATA_WIDTH-1:0] wb_dat_r;

    // ----------------------------------------------------------------
    // DUT instances
    // ----------------------------------------------------------------
    fwvip_wb_initiator_sv #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_initiator (
        .clock (clk),     .reset (reset),
        .adr   (wb_adr),  .cyc   (wb_cyc),   .stb   (wb_stb),
        .we    (wb_we),   .ack   (wb_ack),   .err   (wb_err),
        .sel   (wb_sel),  .dat_w (wb_dat_w), .dat_r (wb_dat_r)
    );

    fwvip_wb_target_sv #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_target (
        .clock (clk),     .reset (reset),
        .adr   (wb_adr),  .cyc   (wb_cyc),   .stb   (wb_stb),
        .we    (wb_we),   .ack   (wb_ack),   .err   (wb_err),
        .sel   (wb_sel),  .dat_w (wb_dat_w), .dat_r (wb_dat_r)
    );

    fwvip_wb_monitor_sv #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_monitor (
        .clock (clk),     .reset (reset),
        .adr   (wb_adr),  .cyc   (wb_cyc),   .stb   (wb_stb),
        .we    (wb_we),   .ack   (wb_ack),   .err   (wb_err),
        .sel   (wb_sel),  .dat_w (wb_dat_w), .dat_r (wb_dat_r)
    );

    fwvip_wb_checker #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_checker (
        .clk   (clk),     .rst   (reset),
        .adr   (wb_adr),  .dat_w (wb_dat_w), .sel   (wb_sel),
        .cyc   (wb_cyc),  .stb   (wb_stb),   .we    (wb_we),
        .dat_r (wb_dat_r),.ack   (wb_ack),   .err   (wb_err),
        .rty   (1'b0)
    );

    // ----------------------------------------------------------------
    // ----------------------------------------------------------------
    // Helper
    // ----------------------------------------------------------------
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

    // ----------------------------------------------------------------
    // Test body
    // ----------------------------------------------------------------
    initial begin
        // Wait for reset deassertion
        while (reset) @(posedge clk);
        repeat (2) @(posedge clk);

        // Run test body and monitor drain concurrently.
        // The monitor thread must span both phases so the egress FIFO
        // (DEPTH=1) is never allowed to fill up between observations.
        fork

            // ---- Test body: writes then reads -----------------------
            begin : test_body

                // --- Write phase ---
                $display("[b2b_sv_tb] --- Write phase ---");
                fork
                    begin : write_driver
                        // REQ_STRUCT packing: {adr, dat, we}
                        u_initiator.bfm_if.req_put({32'h0000_0000, 32'hDEAD_BEEF, 1'b1});
                        u_initiator.bfm_if.req_put({32'h0000_0004, 32'hCAFE_BABE, 1'b1});
                        u_initiator.bfm_if.req_put({32'h0000_0008, 32'h1234_5678, 1'b1});
                        u_initiator.bfm_if.req_put({32'h0000_000C, 32'h9ABC_DEF0, 1'b1});
                    end
                    begin : write_rsp_collector
                        // Drain write responses; no data to check on writes
                        bit [REQ_WIDTH-1:0] rsp;
                        repeat (4) u_initiator.bfm_if.rsp_get(rsp);
                    end
                join

                repeat (4) @(posedge clk);

                // --- Read phase ---
                $display("[b2b_sv_tb] --- Read phase ---");
                fork
                    begin : read_driver
                        u_initiator.bfm_if.req_put({32'h0000_0000, 32'h0, 1'b0});
                        u_initiator.bfm_if.req_put({32'h0000_0004, 32'h0, 1'b0});
                        u_initiator.bfm_if.req_put({32'h0000_0008, 32'h0, 1'b0});
                        u_initiator.bfm_if.req_put({32'h0000_000C, 32'h0, 1'b0});
                    end
                    begin : read_rsp_checker
                        // RSP_STRUCT zero-padded to REQ_WIDTH: {zeros…, dat[31:0], err}
                        // rsp[0]=err, rsp[DATA_WIDTH:1]=dat
                        bit [REQ_WIDTH-1:0] rsp;
                        u_initiator.bfm_if.rsp_get(rsp);
                        check("rd[0x00]", rsp[DATA_WIDTH:1], 32'hDEAD_BEEF);
                        u_initiator.bfm_if.rsp_get(rsp);
                        check("rd[0x04]", rsp[DATA_WIDTH:1], 32'hCAFE_BABE);
                        u_initiator.bfm_if.rsp_get(rsp);
                        check("rd[0x08]", rsp[DATA_WIDTH:1], 32'h1234_5678);
                        u_initiator.bfm_if.rsp_get(rsp);
                        check("rd[0x0C]", rsp[DATA_WIDTH:1], 32'h9ABC_DEF0);
                    end
                join

            end // test_body

            // ---- Monitor drain: runs for the full test duration -----
            begin : monitor_drain
                // MON_STRUCT packing (MSB→LSB): {adr, dat, err, we, cyc_len}
                bit [MON_WIDTH-1:0]  obs;
                bit [ADDR_WIDTH-1:0] obs_adr;
                bit [DATA_WIDTH-1:0] obs_dat;
                bit                  obs_err;
                bit                  obs_we;
                bit [15:0]           obs_cyc_len;

                // 4 write transactions + 4 read transactions = 8 total
                repeat (8) begin
                    u_monitor.bfm_if.get(obs);
                    obs_cyc_len = obs[0  +:  16];
                    obs_we      = obs[16];
                    obs_err     = obs[17];
                    obs_dat     = obs[18 +: DATA_WIDTH];
                    obs_adr     = obs[18 + DATA_WIDTH +: ADDR_WIDTH];
                    $display("MON: adr=0x%08h dat=0x%08h we=%0b err=%0b cyc_len=%0d",
                             obs_adr, obs_dat, obs_we, obs_err, obs_cyc_len);
                end
            end // monitor_drain

        join // outer fork: test_body and monitor_drain

        repeat (4) @(posedge clk);

        if (fail_count == 0)
            $display("[b2b_sv_tb] ALL TESTS PASSED");
        else
            $display("[b2b_sv_tb] %0d TEST(S) FAILED", fail_count);

        $finish;
    end

endmodule
