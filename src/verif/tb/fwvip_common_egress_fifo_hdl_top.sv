`timescale 1ns/1ps
`include "rv_macros.svh"
`include "fwvip_macros.svh"

module fwvip_common_egress_fifo_hdl_top;

    localparam int WIDTH = 32;
    localparam int N_ITEMS = 20;

    logic clock;
    logic reset;

    initial begin
        clock = 0;
        forever #5 clock = ~clock; // 100MHz
    end

    initial begin
        reset = 1'b1;
        $display("[%0t] RESET asserted", $time);
        #50;
        reset = 1'b0;
        $display("[%0t] RESET deasserted", $time);
    end




    // Ready/Valid wires (initiator side drives dat/valid; we drive ready in IF)
    `RV_WIRES(e_, WIDTH)

    // Driver regs for dat/valid (initiator behavior)
    logic [WIDTH-1:0] e_dat_drv;
    logic             e_valid_drv;
    assign e_dat   = e_dat_drv;
    assign e_valid = e_valid_drv;

    // Egress interface instance (drives e_ready, monitors dat/valid)
    fwvip_egress_fifo_if #(
        .WIDTH(WIDTH)
    ) egress_if (
        .clock(clock),
        .reset(reset),
        `RV_CONNECT(e_, e_)
    );

    // Simple source model: produces sequence of items with random stalls
    logic [WIDTH-1:0] src_q[$];

    // Populate source queue
    initial begin
        for (int i=0; i<N_ITEMS; i++) begin
            src_q.push_back($urandom);
        end
    end

    // Initiator send process
    initial begin
        e_dat_drv   = '0;
        e_valid_drv = 1'b0;
        @(negedge reset);
        $display("[%0t] Source start N_ITEMS=%0d", $time, N_ITEMS);
        foreach (src_q[i]) begin
            // Random gap before driving next item
            repeat ($urandom_range(0,3)) @(posedge clock);
            // Wait until consumer is ready, then present data for one cycle
            wait (e_ready);
            @(posedge clock);
            e_dat_drv   = src_q[i];
            e_valid_drv = 1'b1;
            @(posedge clock);
            $display("[%0t] SRC SENT i=%0d data=%0h", $time, i, e_dat_drv);
            e_valid_drv = 1'b0; // remove valid before next item
        end
        $display("[%0t] Source done", $time);
    end

    // Consumer process using BFM get()
    logic [WIDTH-1:0] rx_q[$];
    initial begin
        @(negedge reset);
        $display("[%0t] Consumer start", $time);
        for (int i=0; i<N_ITEMS; i++) begin
            logic [WIDTH-1:0] item;
            egress_if.get(item);
            rx_q.push_back(item);
            $display("[%0t] CONSUMED i=%0d data=%0h", $time, i, item);
        end
        $display("[%0t] Consumer done", $time);
        // Compare queues
        if (rx_q.size() != src_q.size()) begin
            $error("Size mismatch src=%0d rx=%0d", src_q.size(), rx_q.size());
        end else begin
            for (int i=0; i<src_q.size(); i++) begin
                if (src_q[i] !== rx_q[i]) begin
                    $error("Data mismatch idx=%0d src=%0h rx=%0h", i, src_q[i], rx_q[i]);
                end
            end
            $display("[%0t] TEST PASS", $time);
        end
        $finish;
    end


    // Simple progress indicator to avoid silent timeout
    always @(posedge clock) begin
        if (!reset && $time % 1000 == 0) begin
            $display("[%0t] Progress: rx=%0d src=%0d valid=%0b ready=%0b", $time, rx_q.size(), src_q.size(), e_valid, e_ready);
        end
    end

    initial begin
        #10ms;
        $error("Timeout");
        $finish;
    end

endmodule
