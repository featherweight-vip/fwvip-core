/**
 * fwvip_sv_egress_fifo — Egress FIFO BFM (pure SV, no macro dependencies)
 *
 * Captures data produced by the DUT via a ready/valid handshake and makes
 * it available to the testbench via the get() task.
 *
 * Ready/valid handshake (target side):
 *   valid  — asserted by the DUT whenever it has data to send
 *   data   — data word presented by the DUT
 *   ready  — asserted by this BFM when there is space in the internal FIFO
 *
 * get(item):
 *   Blocks until an item is available in the FIFO, then returns it.
 *   Items are returned in arrival order (FIFO order).
 */
interface fwvip_sv_egress_fifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 1
    ) (
        input                   clock,
        input                   reset,
        input                   valid,
        input  [WIDTH-1:0]      data,
        output reg              ready
    );

    localparam int PTR_W   = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int COUNT_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);

    // FIFO storage
    reg [WIDTH-1:0]   fifo [0:DEPTH-1];
    reg [PTR_W-1:0]   rd_ptr;
    reg [PTR_W-1:0]   wr_ptr;
    reg [COUNT_W-1:0] count;

    // get() ↔ always handshake
    reg              get_req;
    reg              get_gnt;
    reg [WIDTH-1:0]  get_data_r;

    // Combinational output: accept data whenever there is space
    assign ready = (count < COUNT_W'(DEPTH));

    // push/pop helpers (blocking-assigned at top of always block)
    reg push_r;
    reg pop_r;

    initial begin
        get_req    = 1'b0;
        get_gnt    = 1'b0;
        get_data_r = '0;
    end

    always @(posedge clock or posedge reset) begin : fifo_ctrl
        if (reset) begin
            rd_ptr  <= '0;
            wr_ptr  <= '0;
            count   <= '0;
            get_gnt <= 1'b0;
        end else begin
            get_gnt <= 1'b0;

            push_r = valid && (count < COUNT_W'(DEPTH));
            pop_r  = get_req && (count != '0);

            if (push_r) begin
                fifo[wr_ptr] <= data;
                wr_ptr       <= (wr_ptr == PTR_W'(DEPTH - 1)) ? '0 : wr_ptr + 1'b1;
            end

            if (pop_r) begin
                get_data_r <= fifo[rd_ptr];
                rd_ptr     <= (rd_ptr == PTR_W'(DEPTH - 1)) ? '0 : rd_ptr + 1'b1;
                get_gnt    <= 1'b1;
            end

            case ({push_r, pop_r})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

    // Blocking get: waits until an item is available, then returns it.
    task get(output bit [WIDTH-1:0] out);
        get_req = 1'b1;
        do @(posedge clock); while (!get_gnt);
        out     = get_data_r;
        get_req = 1'b0;
    endtask

endinterface
