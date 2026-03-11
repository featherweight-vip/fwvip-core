`include "fwvip_wb_macros.svh"


module fwvip_wb_target_core #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int MEM_SIZE   = 256,
        parameter int _REQ_WIDTH = `FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH),
        parameter int _RSP_WIDTH = `FWVIP_WB_RSP_WIDTH(ADDR_WIDTH, DATA_WIDTH)
    ) (
        input                           clock,
        input                           reset,
        input[ADDR_WIDTH-1:0]           adr,
        input                           cyc,
        input                           stb,
        input                           we,
        output reg                      ack,
        output reg                      err,
        input[(DATA_WIDTH/8)-1:0]       sel,
        input[DATA_WIDTH-1:0]           dat_w,
        output reg[DATA_WIDTH-1:0]      dat_r,

        // Request FIFO (unused in direct back-to-back mode)
        input                           req_valid,
        input[_REQ_WIDTH-1:0]           req_data,
        output reg                      req_ready,

        // Response FIFO (unused in direct back-to-back mode)
        output reg                      rsp_valid,
        output reg[_REQ_WIDTH-1:0]      rsp_data,
        input                           rsp_ready
    );

    localparam int WORD_BYTES = DATA_WIDTH / 8;
    localparam int IDX_BITS   = $clog2(MEM_SIZE);
    localparam int OFF_BITS   = $clog2(WORD_BYTES);

    reg [DATA_WIDTH-1:0] mem [0:MEM_SIZE-1];

    wire                    active  = cyc & stb & !ack;
    wire [IDX_BITS-1:0]     mem_idx = adr[IDX_BITS+OFF_BITS-1:OFF_BITS];

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            ack   <= 1'b0;
            err   <= 1'b0;
            dat_r <= {DATA_WIDTH{1'b0}};
        end else begin
            ack <= active;
            err <= 1'b0;
            if (active) begin
                if (we)
                    mem[mem_idx] <= dat_w;
                else
                    dat_r <= mem[mem_idx];
            end
        end
    end

    assign req_ready = 1'b0;
    assign rsp_valid = 1'b0;
    assign rsp_data  = {_REQ_WIDTH{1'b0}};

endmodule
