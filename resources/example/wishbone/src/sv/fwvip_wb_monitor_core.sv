
`include "fwvip_wb_macros.svh"

module fwvip_wb_monitor_core #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int _MON_WIDTH = `FWVIP_WB_MON_WIDTH(ADDR_WIDTH, DATA_WIDTH)
    ) (
        input                      clock,
        input                      reset,
        input[ADDR_WIDTH-1:0]      adr,
        input                      cyc,
        input                      stb,
        input                      we,
        input                      ack,
        input                      err,
        input[(DATA_WIDTH/8)-1:0]  sel,
        input[DATA_WIDTH-1:0]      dat_w,
        input[DATA_WIDTH-1:0]      dat_r,

        // Monitor FIFO
        output reg                      mon_valid,
        output reg[_MON_WIDTH-1:0]      mon_data,
        input                           mon_ready
    );

    // ----------------------------------------------------------------
    // Latched initiator-side fields (captured when stb first asserts)
    // ----------------------------------------------------------------
    reg [ADDR_WIDTH-1:0]    lat_adr;
    reg [DATA_WIDTH-1:0]    lat_dat_w;
    reg                     lat_we;
    reg [15:0]              cyc_cnt;

    // 0 = IDLE (waiting for cyc & stb), 1 = ACTIVE (counting to ack)
    reg mon_state;

    wire trans_done = (ack | err) & cyc & stb;

    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            mon_state <= 1'b0;
            mon_valid <= 1'b0;
            mon_data  <= '0;
            cyc_cnt   <= '0;
            lat_adr   <= '0;
            lat_dat_w <= '0;
            lat_we    <= 1'b0;
        end else begin
            // Consume the output handshake
            if (mon_valid && mon_ready)
                mon_valid <= 1'b0;

            case (mon_state)

            // --------------------------------------------------------
            // IDLE: wait for a new bus cycle
            // --------------------------------------------------------
            1'b0: begin
                if (cyc && stb) begin
                    lat_adr   <= adr;
                    lat_dat_w <= dat_w;
                    lat_we    <= we;
                    cyc_cnt   <= 16'd1;
                    mon_state <= 1'b1;
                end
            end

            // --------------------------------------------------------
            // ACTIVE: count cycles until ack or err
            // --------------------------------------------------------
            1'b1: begin
                if (trans_done) begin
                    mon_valid <= 1'b1;
                    mon_data  <= {
                        lat_adr,
                        (lat_we ? lat_dat_w : dat_r),
                        err,
                        lat_we,
                        cyc_cnt
                    };
                    // Return to IDLE; the IDLE state will immediately
                    // re-enter ACTIVE if stb is still asserted (back-to-back).
                    mon_state <= 1'b0;
                end else begin
                    cyc_cnt <= cyc_cnt + 16'd1;
                end
            end

            endcase
        end
    end

endmodule
