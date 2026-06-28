// Formal verification testbench: fwvip_wb_initiator_core + fwvip_wb_target_core back-to-back
// with fwvip_wb_checker monitoring the Wishbone bus for B.3 protocol compliance.
//
// Free inputs (driven by the formal engine):
//   rst       - held high on cycle 0 via `initial assume`
//   req_valid - unconstrained request-valid signal to initiator
//   req_data  - unconstrained request payload (address / data / write-enable)
//   rsp_ready - unconstrained response back-pressure
//
// The checker's synthesizable assertions (A1-A11) will fail if the combined
// initiator+target system ever violates WB B.3 rules.

`include "fwvip_wb_macros.svh"

module fwvip_wb_formal_b2b_tb #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
);
    localparam int REQ_WIDTH = ADDR_WIDTH + DATA_WIDTH + 1;

    // Global formal clock; (* gclk *) lets Yosys clk2fflogic recognise it.
    (* gclk *) logic clk;

    // System reset and free inputs
    logic rst;
    logic                 req_valid;
    logic [REQ_WIDTH-1:0] req_data;
    logic                 rsp_ready;

    // Wishbone bus signals
    logic [ADDR_WIDTH-1:0]   adr;
    logic [DATA_WIDTH-1:0]   dat_w;
    logic [DATA_WIDTH-1:0]   dat_r;
    logic [DATA_WIDTH/8-1:0] sel;
    logic                    cyc, stb, we;
    logic                    ack, err;

    // DUT 1: initiator — drives master-side bus signals
    fwvip_wb_initiator_core #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_initiator (
        .clock    (clk),
        .reset    (rst),
        .adr      (adr),
        .cyc      (cyc),
        .stb      (stb),
        .we       (we),
        .ack      (ack),
        .err      (err),
        .sel      (sel),
        .dat_w    (dat_w),
        .dat_r    (dat_r),
        .req_valid(req_valid),
        .req_data (req_data),
        .req_ready(),
        .rsp_valid(),
        .rsp_data (),
        .rsp_ready(rsp_ready)
    );

    // DUT 2: target — drives slave-side bus signals, shares bus with initiator
    fwvip_wb_target_core #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_target (
        .clock    (clk),
        .reset    (rst),
        .adr      (adr),
        .cyc      (cyc),
        .stb      (stb),
        .we       (we),
        .ack      (ack),
        .err      (err),
        .sel      (sel),
        .dat_w    (dat_w),
        .dat_r    (dat_r),
        .req_valid(1'b0),
        .req_data ({REQ_WIDTH{1'b0}}),
        .req_ready(),
        .rsp_valid(),
        .rsp_data (),
        .rsp_ready(1'b0)
    );

    // Protocol checker — synthesizable RTL assertions (A1-A11, WB B.3)
    fwvip_wb_checker #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_checker (
        .clk  (clk),
        .rst  (rst),
        .adr  (adr),
        .dat_w(dat_w),
        .sel  (sel),
        .cyc  (cyc),
        .stb  (stb),
        .we   (we),
        .dat_r(dat_r),
        .ack  (ack),
        .err  (err),
        .rty  (1'b0)
    );

    // System starts in reset so that A2/A3 (CYC/STB negated after RST) hold
    // from the very first cycle.
    initial assume(rst);

endmodule
