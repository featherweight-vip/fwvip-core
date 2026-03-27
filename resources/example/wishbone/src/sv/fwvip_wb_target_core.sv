`include "fwvip_wb_macros.svh"


module fwvip_wb_target_core #(
        parameter int  ADDR_WIDTH = 32,
        parameter int  DATA_WIDTH = 32,
        parameter int  MEM_SIZE   = 256,
        // When REACTIVE=1 the core pushes observed bus requests to the req FIFO
        // and waits for responses injected via the rsp FIFO instead of using the
        // internal memory model.  Port directions for req_* and rsp_* flip
        // accordingly (see comments below).
        parameter bit  REACTIVE   = 1'b0,
        parameter int  _REQ_WIDTH = `FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH),
        parameter int  _RSP_WIDTH = `FWVIP_WB_RSP_WIDTH(ADDR_WIDTH, DATA_WIDTH)
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

        // REACTIVE=0: req_valid/req_data are inputs (unused); req_ready is output (tied 0).
        // REACTIVE=1: req_valid/req_data are outputs (observed bus request → TB);
        //             req_ready is input (egress FIFO → core, space available).
        output reg                      req_valid,
        output reg [_REQ_WIDTH-1:0]     req_data,
        input                           req_ready,

        // REACTIVE=0: rsp_valid/rsp_data are outputs (tied 0); rsp_ready is input (unused).
        // REACTIVE=1: rsp_valid/rsp_data are inputs (TB-injected response → core);
        //             rsp_ready is output (core → ingress FIFO, consumed response).
        input                           rsp_valid,
        input  [_RSP_WIDTH-1:0]         rsp_data,
        output reg                      rsp_ready
    );

    localparam int WORD_BYTES = DATA_WIDTH / 8;
    localparam int IDX_BITS   = $clog2(MEM_SIZE);
    localparam int OFF_BITS   = $clog2(WORD_BYTES);

    // ----------------------------------------------------------------
    // REACTIVE=0 — direct memory model (original behaviour)
    // ----------------------------------------------------------------
    generate if (!REACTIVE) begin : g_direct

        reg [DATA_WIDTH-1:0] mem [0:MEM_SIZE-1];
        wire active  = cyc & stb & !ack;
        wire [IDX_BITS-1:0] mem_idx = adr[IDX_BITS+OFF_BITS-1:OFF_BITS];

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

        // Tie off reactive FIFO ports
        assign req_valid = 1'b0;
        assign req_data  = {_REQ_WIDTH{1'b0}};
        assign rsp_ready = 1'b0;

    end endgenerate

    // ----------------------------------------------------------------
    // REACTIVE=1 — handler-sequence mode
    //
    // FSM:
    //   IDLE      : waiting for cyc & stb
    //   PUSH_REQ  : asserting req_valid to push observed request into egress FIFO
    //   WAIT_RSP  : waiting for TB-injected response (rsp_valid from ingress FIFO)
    // ----------------------------------------------------------------
    generate if (REACTIVE) begin : g_reactive

        localparam bit [1:0] ST_IDLE     = 2'd0;
        localparam bit [1:0] ST_PUSH_REQ = 2'd1;
        localparam bit [1:0] ST_WAIT_RSP = 2'd2;

        reg [1:0]            state;
        reg [_REQ_WIDTH-1:0] req_latch;  // latched request while waiting for FIFO

        always @(posedge clock or posedge reset) begin
            if (reset) begin
                state     <= ST_IDLE;
                req_latch <= {_REQ_WIDTH{1'b0}};
                req_valid <= 1'b0;
                req_data  <= {_REQ_WIDTH{1'b0}};
                rsp_ready <= 1'b0;
                ack       <= 1'b0;
                err       <= 1'b0;
                dat_r     <= {DATA_WIDTH{1'b0}};
            end else begin
                // Defaults — overridden per state below
                req_valid <= 1'b0;
                rsp_ready <= 1'b0;
                ack       <= 1'b0;
                err       <= 1'b0;

                case (state)
                    ST_IDLE: begin
                        // !ack prevents re-latching on the cycle ack was just asserted
                        if (cyc && stb && !ack) begin
                            req_latch <= {adr[ADDR_WIDTH-1:0],
                                         dat_w[DATA_WIDTH-1:0],
                                         we};
                            state <= ST_PUSH_REQ;
                        end
                    end

                    ST_PUSH_REQ: begin
                        req_valid <= 1'b1;
                        req_data  <= req_latch;
                        if (req_valid && req_ready)
                            state <= ST_WAIT_RSP;
                    end

                    ST_WAIT_RSP: begin
                        if (rsp_valid) begin
                            // Consume the response; terminate with either ACK or ERR.
                            rsp_ready <= 1'b1;
                            // RSP_STRUCT packed: {dat[DATA_WIDTH-1:0], err}
                            ack       <= !rsp_data[0];
                            dat_r     <= rsp_data[_RSP_WIDTH-1:1];
                            err       <= rsp_data[0];
                            state     <= ST_IDLE;
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end

    end endgenerate

endmodule
