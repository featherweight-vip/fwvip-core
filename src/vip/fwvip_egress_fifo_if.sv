`include "rv_macros.svh"
`include "fwvip_macros.svh"

/**
 * Egress FIFO BFM (consumer side)
 *
 * - WIDTH-wide data
 * - DEPTH-deep synchronous FIFO
 * - Drives e_ready when space is available or a get() is pending
 * - Captures items on e_valid && e_ready
 * - get() blocks until an item is available (supports same-cycle bypass)
 */
interface fwvip_egress_fifo_if #(
        parameter int WIDTH = 32,
        parameter int DEPTH = 1
    ) (
        input               clock,
        input               reset,
        // Target (consumer) port: we receive dat/valid and drive ready
        `RV_TARGET_PORT(e_, WIDTH)
    );

    // Derived widths
    localparam int PTR_W   = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int COUNT_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH+1);

    // Storage
    logic [WIDTH-1:0]     fifo [0:DEPTH-1];
    logic [PTR_W-1:0]     rd_ptr, wr_ptr;
    logic [COUNT_W-1:0]   count;

    // Combinational flags for push/pop
    logic                 push_do, pop_do;

    // Internal handshake for get()
    logic                 get_req;
    logic                 get_gnt;
    logic [WIDTH-1:0]     get_data;

    // Ready output: space available or consumer is taking one this cycle
    wire                  ready_comb = ((int'(count) < DEPTH) || get_req);
    assign e_ready = ready_comb;

    // Optional: initialize task-driven signals
    initial begin
        get_req  = 1'b0;
        get_data = '0;
    end

    // Synchronous FIFO control with empty/full same-cycle handling
    integer ii;
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            rd_ptr  <= '0;
            wr_ptr  <= '0;
            count   <= '0;
            get_gnt <= 1'b0;
            // Clear storage to avoid X-propagation (optional)
            for (ii = 0; ii < DEPTH; ii = ii + 1) begin
                fifo[ii] <= '0;
            end
        end else begin
            get_gnt <= 1'b0;

            // Determine push/pop for this cycle (based on pre-update state)
            // Allow push in same cycle as pop when FIFO was full (due to get_req)
            push_do = (e_valid && e_ready);
            // Allow pop when data exists or when we will accept a new item (empty-bypass)
            pop_do  = (get_req && ((count != '0) || e_valid));

            // Push (write incoming data) unless we're in empty-bypass with concurrent pop
            if (push_do) begin
                if (!(pop_do && (count == '0))) begin
                    fifo[wr_ptr] <= e_dat;
                    if (wr_ptr == PTR_W'(DEPTH-1))
                        wr_ptr <= '0;
                    else
                        wr_ptr <= wr_ptr + 1'b1;
                end
            end

            // Pop (provide to get())
            if (pop_do) begin
                if (count != '0) begin
                    get_data <= fifo[rd_ptr];
                    if (rd_ptr == PTR_W'(DEPTH-1))
                        rd_ptr <= '0;
                    else
                        rd_ptr <= rd_ptr + 1'b1;
                end else begin
                    // Empty-bypass: deliver incoming item directly
                    get_data <= e_dat;
                end
                get_gnt <= 1'b1;
            end

            // Occupancy
            case ({push_do, pop_do})
                2'b10: count <= count + 1'b1; // push only
                2'b01: count <= count - 1'b1; // pop only
                default: count <= count;      // same or none
            endcase
        end
    end

    // Blocking get: waits until an item is returned
    task automatic get(output reg [WIDTH-1:0] data);
        if (reset) @(negedge reset);
        get_req = 1'b1;
        // Hold request until granted
        do @(posedge clock) begin
            get_req = 1'b1;
        end while (!get_gnt);
        data   = get_data;
        get_req = 1'b0;
    endtask

    // Debug: monitor pushes/pops
    `ifdef FWVIP_DEBUG
    always @(posedge clock) begin
        if (!reset) begin
            if (push_do) $display("[%0t] EF push_do dat=%0h wr_ptr=%0d count_next=%0d", $time, e_dat, wr_ptr, count + 1);
            if (pop_do && (count != 0)) $display("[%0t] EF pop_do rd_ptr=%0d dat=%0h count_next=%0d", $time, rd_ptr, get_data, count - 1);
            if (pop_do && (count == 0)) $display("[%0t] EF bypass dat=%0h", $time, get_data);
        end
    end
    `endif

endinterface
