`include "rv_macros.svh"
`include "fwvip_macros.svh"

/**
 * Ingress FIFO BFM used with a full SV/UVM environment
 *
 * - WIDTH-wide data
 * - DEPTH-deep synchronous FIFO
 * - Asserts i_valid whenever data is available
 * - Advances to next item when i_valid && i_ready
 * - put() blocks until there is space and the item is accepted
 */
interface fwvip_ingress_fifo_if #(
        parameter int WIDTH = 32,
        parameter int DEPTH = 1
    ) (
        input               clock,
        input               reset,
        `RV_INITIATOR_PORT(i_, WIDTH)
    );

    // Derived widths
    localparam int PTR_W   = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int COUNT_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH+1);

    // Storage
    logic [WIDTH-1:0] fifo [0:DEPTH-1];
    logic [PTR_W-1:0] rd_ptr, wr_ptr;
    logic [COUNT_W-1:0] count;

    // Combinational flags for push/pop
    logic                 push_do, pop_do;

    // Internal handshake for put()
    logic                 put_req;
    logic                 put_gnt;
    logic [WIDTH-1:0]     put_data;

    // Ready/Valid outputs
    assign i_valid = (count != 0);
    assign i_dat   = fifo[rd_ptr];

    // Optional: initialize task-driven signals
    initial begin
        put_req  = 1'b0;
        put_data = '0;
    end

    // Synchronous FIFO control
    integer ii;
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            rd_ptr  <= '0;
            wr_ptr  <= '0;
            count   <= '0;
            put_gnt <= 1'b0;
            // Clear storage to avoid X-propagation (optional)
            for (ii = 0; ii < DEPTH; ii = ii + 1) begin
                fifo[ii] <= '0;
            end
            // Default outputs
            put_gnt <= 1'b0;

        end else begin
            put_gnt <= 1'b0;

            // Determine push/pop for this cycle (based on pre-update state)
            // Allow push in same cycle as pop when FIFO was full
            pop_do  = ((count != '0) && i_ready);
            push_do = (put_req && ((int'(count) < DEPTH) || pop_do));

            // Push
            if (push_do) begin
                fifo[wr_ptr] <= put_data;
                if (wr_ptr == PTR_W'(DEPTH-1))
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
                put_gnt <= 1'b1;
            end

            // Pop
            if (pop_do) begin
                if (rd_ptr == PTR_W'(DEPTH-1))
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

            // Occupancy
            case ({push_do, pop_do})
                2'b10: count <= count + 1'b1; // push only
                2'b01: count <= count - 1'b1; // pop only
                default: count <= count;      // same or both
            endcase
        end
    end

    // Blocking put: waits until space is available and the item is accepted
    task put(input reg [WIDTH-1:0] data);
        // Present request and hold until granted
        put_data = data;
        put_req  = 1'b1;
        // Wait until a clock edge where acceptance is asserted
        do @(posedge clock) begin
            // Note: Verilator (5.040) doesn't like empty while loops
            put_req = 1'b1; 
        end while (!put_gnt);
        // Deassert request after acceptance
        put_req  = 1'b0;
    endtask

    // Debug: monitor puts/pops
    `ifdef FWVIP_DEBUG
    always @(posedge clock) begin
        if (!reset) begin
            if (put_req) $display("[%0t] IF put_req data=%0h count=%0d", $time, put_data, count);
            if (put_gnt) $display("[%0t] IF put_gnt accepted data=%0h wr_ptr=%0d count_next=%0d", $time, put_data, wr_ptr, count + 1);
            if (pop_do) $display("[%0t] IF pop_do rd_ptr=%0d dat=%0h count_next=%0d", $time, rd_ptr, i_dat, count - 1);
        end
    end
    `endif


endinterface
