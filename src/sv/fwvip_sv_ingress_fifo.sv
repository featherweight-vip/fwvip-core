

/**
 * fwvip_sv_ingress_fifo — Ingress FIFO BFM (pure SV, no macro dependencies)
 *
 * Implements a DEPTH-item synchronous FIFO driven by the put() task.
 *
 * Ready/valid handshake (initiator side):
 *   valid  — asserted whenever the FIFO is non-empty
 *   data   — head item presented to the consumer
 *   ready  — consumer asserts to pop the head item
 *
 * put(item):
 *   Consumes exactly one clock cycle to push the item into the FIFO.
 *   Blocks (holds across multiple cycles) if the FIFO is full until
 *   a pop creates space.
 */
interface fwvip_sv_ingress_fifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 1
    ) (
        input                   clock,
        input                   reset,
        output reg              valid,
        output reg[WIDTH-1:0]   data,
        input                   ready
    );

    localparam int PTR_W   = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int COUNT_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);

    // FIFO storage
    reg [WIDTH-1:0]   fifo [0:DEPTH-1];
    reg [PTR_W-1:0]   rd_ptr;
    reg [PTR_W-1:0]   wr_ptr;
    reg [COUNT_W-1:0] count;

    // put() ↔ always handshake
    reg              put_req;
    reg              put_gnt;
    reg [WIDTH-1:0]  put_data;

    // Combinational outputs
    assign valid = (count != '0);
    assign data  = fifo[rd_ptr];

    // push/pop helpers (blocking-assigned at top of always block)
    reg push_r;
    reg pop_r;

    initial begin
        put_req  = 1'b0;
        put_gnt  = 1'b0;
        put_data = '0;
    end

    always @(posedge clock or posedge reset) begin : fifo_ctrl
        if (reset) begin
            rd_ptr  <= '0;
            wr_ptr  <= '0;
            count   <= '0;
            put_gnt <= 1'b0;
        end else begin
            put_gnt <= 1'b0;

            pop_r  = valid && ready;
            // Allow push in same cycle as a pop so full FIFO can accept
            // immediately once the consumer takes an item.
            push_r = put_req && ((count < COUNT_W'(DEPTH)) || pop_r);

            if (push_r) begin
                fifo[wr_ptr] <= put_data;
                wr_ptr       <= (wr_ptr == PTR_W'(DEPTH - 1)) ? '0 : wr_ptr + 1'b1;
                put_gnt      <= 1'b1;
            end

            if (pop_r)
                rd_ptr <= (rd_ptr == PTR_W'(DEPTH - 1)) ? '0 : rd_ptr + 1'b1;

            case ({push_r, pop_r})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

    // Blocking put: presents the item for one accepted clock cycle.
    // Waits across as many cycles as needed until there is space.
    task put(bit [WIDTH-1:0] data);
        put_data = data;
        put_req  = 1'b1;
        do @(posedge clock); while (!put_gnt);
        put_req  = 1'b0;
    endtask

endinterface

