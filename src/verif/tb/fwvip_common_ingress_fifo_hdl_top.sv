`timescale 1ns/1ps
`include "rv_macros.svh"
`include "fwvip_macros.svh"

module fwvip_common_ingress_fifo_hdl_top;

    // ------------------------------------------------------------------------
    // Parameters (adjust as needed; can be made plusargs later)
    // ------------------------------------------------------------------------
    localparam int WIDTH = 32;
    localparam int DEPTH = 4;

    // ------------------------------------------------------------------------
    // Clock / Reset
    // ------------------------------------------------------------------------
    logic clock;
    logic reset;

    initial begin
        clock = 0;
        forever #5 clock = ~clock; // 100MHz
    end

`ifdef TRACE_ENABLED
    initial begin
        $dumpfile("sim.vcd");
        $dumpvars;
    end
`endif // TRACE_ENABLED

    initial begin
        reset = 1'b1;
        repeat (5) @(posedge clock);
        reset = 1'b0;
    end

`ifdef FWVIP_TB_DEBUG
    // Clock monitor
    int clk_cnt;
    initial clk_cnt = 0;
    always @(posedge clock) begin
        if (clk_cnt < 10) begin
            $display("[%0t] clk posedge reset=%0b", $time, reset);
            clk_cnt++;
        end
    end

    // Debug reset monitor
    initial begin
        $display("[%0t] reset init=%0b", $time, reset);
        forever begin
            @(reset);
            $display("[%0t] reset change -> %0b", $time, reset);
        end
    end
`endif


    // ------------------------------------------------------------------------
    // Ready/Valid wires using RV macros
    // i_dat, i_valid, i_ready become wires
    // We drive i_ready via a driver reg
    // ------------------------------------------------------------------------
    `RV_WIRES(i_, WIDTH)
    logic ready_drv;
    assign i_ready = ready_drv;

    // ------------------------------------------------------------------------
    // Interface Instance (FIFO behavioral model lives inside)
    // ------------------------------------------------------------------------
    fwvip_ingress_fifo_if #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) ingress_if (
        .clock(clock),
        .reset(reset),
        `RV_CONNECT(i_, i_)
    );

    // ------------------------------------------------------------------------
    // Ready driving modes
    // ------------------------------------------------------------------------
    typedef enum int {READY_ALWAYS, READY_RANDOM, READY_BURST} ready_mode_t;
    ready_mode_t ready_mode;

    task automatic set_ready_mode(ready_mode_t m);
        ready_mode = m;
`ifdef FWVIP_TB_DEBUG
        $display("[%0t] Set ready_mode=%0d", $time, ready_mode);
`endif
    endtask

    int burst_cnt;
    localparam int BURST_ON  = 3;
    localparam int BURST_OFF = 2;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            ready_drv <= 1'b0;
            burst_cnt <= 0;
        end
        else begin
            case (ready_mode)
                READY_ALWAYS: ready_drv <= 1'b1;
                READY_RANDOM: ready_drv <= ($urandom_range(0,1) != 0);
                READY_BURST: begin
                    if (burst_cnt < BURST_ON) begin
                        ready_drv <= 1'b1;
                        burst_cnt <= burst_cnt + 1;
                    end
                    else if (burst_cnt < BURST_ON + BURST_OFF) begin
                        ready_drv <= 1'b0;
                        burst_cnt <= burst_cnt + 1;
                    end
                    else begin
                        burst_cnt <= 0;
                        ready_drv <= 1'b1;
                    end
                end
                default: ready_drv <= 1'b1;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Scoreboard / Expected Queue
    // ------------------------------------------------------------------------
    logic [WIDTH-1:0] exp_q[$];
    int mirror_count; // mirrors FIFO occupancy from pushes/pops observed via handshake


    // Handshake monitor with one-cycle pipeline to avoid race with DUT updates
    logic                i_valid_q, i_ready_q;
    logic [WIDTH-1:0]    i_dat_q;
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            i_valid_q <= 1'b0;
            i_ready_q <= 1'b0;
            i_dat_q   <= '0;
        end else begin
            // Process handshake from previous cycle using captured data
            if (i_valid_q && i_ready_q) begin
                if (exp_q.size() == 0) begin
                    $error("[%0t] POP with empty expect queue", $time);
                    $finish;
                end
                if (i_dat_q !== exp_q[0]) begin
                    $error("[%0t] Data mismatch: got=%0h exp=%0h", $time, i_dat_q, exp_q[0]);
                    $finish;
                end
                exp_q.pop_front();
                mirror_count--;
`ifdef FWVIP_TB_DEBUG
                $display("[%0t] POP %0h count=%0d remaining=%0d", $time, i_dat_q, mirror_count, exp_q.size());
`endif
            end
            // Capture current values for next cycle
            i_valid_q <= i_valid;
            i_ready_q <= i_ready;
            i_dat_q   <= i_dat;
        end
    end

    // ------------------------------------------------------------------------
    // Put sequence task
    // Calls the interface's blocking put()
    // ------------------------------------------------------------------------
    task automatic put_seq(int unsigned n);
`ifdef FWVIP_TB_DEBUG
        $display("[%0t] put_seq start n=%0d", $time, n);
`endif
        for (int j = 0; j < n; j++) begin
            logic [WIDTH-1:0] data = $urandom;
`ifdef FWVIP_TB_DEBUG
            $display("[%0t] put_seq j=%0d issue put data=%0h count=%0d", $time, j, data, mirror_count);
`endif
            ingress_if.put(data); // blocks until space & acceptance
            exp_q.push_back(data);
            mirror_count++;
`ifdef FWVIP_TB_DEBUG
            $display("[%0t] PUSH %0h count=%0d queued=%0d", $time, data, mirror_count, exp_q.size());
`endif
            // Note: allow transient mirror_count=DEPTH+1 when push and pop occur in same cycle
            if (mirror_count > (DEPTH+1)) begin
                $error("[%0t] Mirror occupancy overflow mirror_count=%0d DEPTH=%0d", $time, mirror_count, DEPTH);
                $finish;
            end
        end
`ifdef FWVIP_TB_DEBUG
        $display("[%0t] put_seq end n=%0d", $time, n);
`endif
    endtask

    // Wait for drain (empty expect and mirror_count zero)
    task automatic wait_drain();
        wait(exp_q.size() == 0 && mirror_count == 0);
        // settle a couple cycles
        repeat (2) @(posedge clock);
    endtask

    // ------------------------------------------------------------------------
    // Individual Tests
    // ------------------------------------------------------------------------
    task automatic test_basic();
`ifdef FWVIP_TB_DEBUG
        $display("[%0t] BEGIN test_basic", $time);
`endif
        set_ready_mode(READY_ALWAYS);
        put_seq(DEPTH);         // fill
        wait_drain();           // drain
        put_seq(DEPTH*2);       // overfill cycles (wrap checks)
        wait_drain();
`ifdef FWVIP_TB_DEBUG
        $display("[%0t] END test_basic", $time);
`endif
    endtask

    task automatic test_random_ready();
`ifdef FWVIP_TB_DEBUG
        $display("[%0t] BEGIN test_random_ready", $time);
`endif
        set_ready_mode(READY_RANDOM);
        put_seq(DEPTH*3);
        wait_drain();
`ifdef FWVIP_TB_DEBUG
        $display("[%0t] END test_random_ready", $time);
`endif
    endtask

    task automatic test_burst_backpressure();
`ifdef FWVIP_TB_DEBUG
        $display("[%0t] BEGIN test_burst_backpressure", $time);
`endif
        set_ready_mode(READY_BURST);
        put_seq(DEPTH*3);
        wait_drain();
`ifdef FWVIP_TB_DEBUG
        $display("[%0t] END test_burst_backpressure", $time);
`endif
    endtask

    // ------------------------------------------------------------------------
    // Top-level test sequence
    // ------------------------------------------------------------------------
    initial begin
`ifdef FWVIP_TB_DEBUG
        $display("[%0t] TB start", $time);
`endif
        mirror_count = 0;
`ifdef FWVIP_TB_DEBUG
        $display("[%0t] Waiting for reset deassert (negedge)", $time);
`endif
        // Wait for reset deassert; avoid time-0 race by waiting a clock first
        @(posedge clock);
        if (reset) begin
`ifdef FWVIP_TB_DEBUG
            $display("[%0t] Reset asserted; waiting for deassert...", $time);
`endif
            @(negedge reset);
        end
`ifdef FWVIP_TB_DEBUG
        $display("[%0t] Reset deasserted", $time);
`endif
        // Run tests
        test_basic();
        test_random_ready();
        test_burst_backpressure();
        // Final check
        if (exp_q.size() == 0 && mirror_count == 0) begin
            $display("[%0t] TESTBENCH PASS", $time);
        end
        else begin
            $error("[%0t] TESTBENCH FAIL: exp_q.size()=%0d mirror_count=%0d",
                    $time, exp_q.size(), mirror_count);
        end
        $finish;
    end

    initial begin
        #10ms;
        $display("Fatal: timeout");
        $finish;
    end

endmodule
