`include "fwvip_wb_macros.svh"

module fwvip_wb_initiator_core #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int _REQ_WIDTH = `FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH),
        parameter int _RSP_WIDTH = `FWVIP_WB_RSP_WIDTH(ADDR_WIDTH, DATA_WIDTH)
    ) (
        input                           clock,
        input                           reset,
        output reg[ADDR_WIDTH-1:0]      adr,
        output reg                      cyc,
        output reg                      stb,
        output reg                      we,
        input                           ack,
        input                           err,
        output reg[(DATA_WIDTH/8)-1:0]  sel,
        output reg[DATA_WIDTH-1:0]      dat_w,
        input[DATA_WIDTH-1:0]           dat_r,

        // Request FIFO
        input                           req_valid,
        input[_REQ_WIDTH-1:0]           req_data,
        output reg                      req_ready,

        // Response FIFO
        output reg                      rsp_valid,
        output reg[_REQ_WIDTH-1:0]      rsp_data,
        input                           rsp_ready
    );

    reg    req_state;
    reg[3:0]    rsp_state;

    `FWVIP_WB_REQ_STRUCT(ADDR_WIDTH, DATA_WIDTH) req;
    assign req = req_data;

    `FWVIP_WB_RSP_STRUCT(ADDR_WIDTH, DATA_WIDTH) rsp_a, rsp_l;

    assign rsp_a = {dat_r, err};

    wire req_ack = ((ack | err) && cyc && stb);
    assign req_ready = (req_valid &&
        (req_state == 1'b0 ||
        (req_state == 1'b1 && req_ack)));

    // Request state machine
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            req_state <= 1'b0;
            adr       <= {ADDR_WIDTH{1'b0}};
            cyc       <= 1'b0;
            stb       <= 1'b0;
            we        <= 1'b0;
            sel       <= {(DATA_WIDTH/8){1'b1}};
            dat_w     <= {DATA_WIDTH{1'b0}};
            rsp_valid <= 1'b0;
        end else begin
            case (req_state)
            1'h0: begin
                if (req_valid) begin
                    adr       <= req.adr;
                    we        <= req.we;
                    cyc       <= 1'b1;
                    stb       <= 1'b1;
                    dat_w     <= req.dat;
                    req_state <= 1'b1;
                end
            end

            1'h1: begin
                // Wait for ack
                if (req_ack) begin
                    // The response FSM handles the response data.
                    // We worry about the next request
                    if (req_valid) begin
                        // Issue the next request
                        adr   <= req.adr;
                        we    <= req.we;
                        cyc   <= 1'b1;
                        stb   <= 1'b1;
                        dat_w <= req.dat;
                    end else begin
                        cyc       <= 1'b0;
                        stb       <= 1'b0;
                        req_state <= 1'b0;
                    end
                end
            end
            endcase

            // Response FIFO: latch on ack, hold until rsp_ready consumed
            if (req_ack) begin
                rsp_valid <= 1'b1;
                rsp_l     <= rsp_a;
            end else if (rsp_valid && rsp_ready) begin
                rsp_valid <= 1'b0;
            end
        end
    end

    assign rsp_data = {{(_REQ_WIDTH - _RSP_WIDTH){1'b0}}, rsp_l};


endmodule
