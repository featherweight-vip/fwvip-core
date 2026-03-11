
`include "fwvip_wb_macros.svh"

module b2b_tb;

    // Parameters
    localparam int ADDR_WIDTH     = 32;
    localparam int DATA_WIDTH     = 32;
    localparam int SEL_WIDTH      = DATA_WIDTH / 8;
    // FWVIP_WB_REQ_STRUCT(32,32) packed bits: {adr[31:0], dat[31:0], we} = 65 bits
    localparam int REQ_WIDTH      = ADDR_WIDTH + DATA_WIDTH + 1;
    localparam int TIMEOUT_CYCLES = 10_000;

    // Clock and reset
    logic clk;
    logic reset;

    // Wishbone bus
    logic [ADDR_WIDTH-1:0] wb_adr;
    logic                  wb_cyc;
    logic                  wb_stb;
    logic                  wb_we;
    logic                  wb_ack;
    logic                  wb_err;
    logic [SEL_WIDTH-1:0]  wb_sel;
    logic [DATA_WIDTH-1:0] wb_dat_w;
    logic [DATA_WIDTH-1:0] wb_dat_r;

    // Initiator FIFO interface
    logic                  init_req_valid;
    logic [REQ_WIDTH-1:0]  init_req_data;
    logic                  init_req_ready;
    logic                  init_rsp_valid;
    logic [REQ_WIDTH-1:0]  init_rsp_data;
    logic                  init_rsp_ready;

    // ----------------------------------------------------------------
    // Clock: 10 ns period
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Reset: active-high for 8 clock cycles
    // ----------------------------------------------------------------
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

    // ----------------------------------------------------------------
    // Timeout watchdog
    // ----------------------------------------------------------------
    int unsigned cycle_count = 0;
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (cycle_count >= TIMEOUT_CYCLES) begin
            $display("ERROR [%0t]: testbench timeout after %0d cycles",
                     $time, TIMEOUT_CYCLES);
            $finish(1);
        end
    end

    // ----------------------------------------------------------------
    // DUT: initiator
    // ----------------------------------------------------------------
    fwvip_wb_initiator_core #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_initiator (
        .clock      (clk),
        .reset      (reset),
        .adr        (wb_adr),
        .cyc        (wb_cyc),
        .stb        (wb_stb),
        .we         (wb_we),
        .ack        (wb_ack),
        .err        (wb_err),
        .sel        (wb_sel),
        .dat_w      (wb_dat_w),
        .dat_r      (wb_dat_r),
        .req_valid  (init_req_valid),
        .req_data   (init_req_data),
        .req_ready  (init_req_ready),
        .rsp_valid  (init_rsp_valid),
        .rsp_data   (init_rsp_data),
        .rsp_ready  (init_rsp_ready)
    );

    // ----------------------------------------------------------------
    // DUT: target (back-to-back)
    // ----------------------------------------------------------------
    fwvip_wb_target_core #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_target (
        .clock      (clk),
        .reset      (reset),
        .adr        (wb_adr),
        .cyc        (wb_cyc),
        .stb        (wb_stb),
        .we         (wb_we),
        .ack        (wb_ack),
        .err        (wb_err),
        .sel        (wb_sel),
        .dat_w      (wb_dat_w),
        .dat_r      (wb_dat_r),
        .req_valid  (1'b0),
        .req_data   ({REQ_WIDTH{1'b0}}),
        .req_ready  (),
        .rsp_valid  (),
        .rsp_data   (),
        .rsp_ready  (1'b1)
    );

    // ----------------------------------------------------------------
    // Protocol checker — monitors WB B.3 compliance on every cycle.
    // Uses the synthesizable RTL path (no WB_CHECKER_SVA); assertions
    // fire as immediate asserts inside always_ff blocks, compatible
    // with Verilator's --assert mode.
    // ----------------------------------------------------------------
    fwvip_wb_checker #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_checker (
        .clk   (clk),
        .rst   (reset),
        .adr   (wb_adr),
        .dat_w (wb_dat_w),
        .sel   (wb_sel),
        .cyc   (wb_cyc),
        .stb   (wb_stb),
        .we    (wb_we),
        .dat_r (wb_dat_r),
        .ack   (wb_ack),
        .err   (wb_err),
        .rty   (1'b0)
    );

    // ----------------------------------------------------------------
    // Task: issue one request through the initiator FIFO
    //   req_data packing matches FWVIP_WB_REQ_STRUCT: {adr, dat, we}
    //   Uses non-blocking assignments so signals are driven after the
    //   clock edge (correct setup timing in a multi-simulator flow).
    //   In Verilator, NBAs in initial-block tasks are treated as
    //   blocking, which is functionally equivalent here.
    // ----------------------------------------------------------------
    // verilator lint_off INITIALDLY
    task automatic issue_req(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input logic                  wr
    );
        @(posedge clk);
        init_req_valid <= 1'b1;
        init_req_data  <= {addr, data, wr};
        @(posedge clk);
        while (!init_req_ready) @(posedge clk);
        init_req_valid <= 1'b0;
        init_req_data  <= '0;
    endtask
    // verilator lint_on INITIALDLY

    // ----------------------------------------------------------------
    // Task: wait for one response (rsp_valid is combinatorial with ack)
    //   rsp_data packing: upper bits zero-extended, LSBs = FWVIP_WB_RSP_STRUCT{dat,err}
    // ----------------------------------------------------------------
    task automatic wait_rsp(
        output logic [DATA_WIDTH-1:0] rdata,
        output logic                  rsp_err
    );
        @(posedge clk);
        while (!init_rsp_valid) @(posedge clk);
        rsp_err = init_rsp_data[0];
        rdata   = init_rsp_data[DATA_WIDTH:1];
    endtask

    // ----------------------------------------------------------------
    // Test body
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

    initial begin
        logic [DATA_WIDTH-1:0] rdata;
        logic                  rerr;

        init_req_valid = 1'b0;
        init_req_data  = '0;
        init_rsp_ready = 1'b1;

        // Wait for reset to deassert
        while (reset) @(posedge clk);
        repeat (2) @(posedge clk);

        $display("[b2b_tb] --- Write phase ---");
        issue_req(32'h0000_0000, 32'hDEAD_BEEF, 1'b1);
        issue_req(32'h0000_0004, 32'hCAFE_BABE, 1'b1);
        issue_req(32'h0000_0008, 32'h1234_5678, 1'b1);
        issue_req(32'h0000_000C, 32'h9ABC_DEF0, 1'b1);

        repeat (4) @(posedge clk);

        $display("[b2b_tb] --- Read-back phase ---");
        issue_req(32'h0000_0000, '0, 1'b0);
        wait_rsp(rdata, rerr);
        check("rd[0x00]", rdata, 32'hDEAD_BEEF);

        issue_req(32'h0000_0004, '0, 1'b0);
        wait_rsp(rdata, rerr);
        check("rd[0x04]", rdata, 32'hCAFE_BABE);

        issue_req(32'h0000_0008, '0, 1'b0);
        wait_rsp(rdata, rerr);
        check("rd[0x08]", rdata, 32'h1234_5678);

        issue_req(32'h0000_000C, '0, 1'b0);
        wait_rsp(rdata, rerr);
        check("rd[0x0C]", rdata, 32'h9ABC_DEF0);

        repeat (4) @(posedge clk);

        if (fail_count == 0)
            $display("[b2b_tb] ALL TESTS PASSED");
        else
            $display("[b2b_tb] %0d TEST(S) FAILED", fail_count);

        $finish;
    end

endmodule

