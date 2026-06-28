`include "uvm_macros.svh"

module b2b_targ_uvm_tb;
  import uvm_pkg::*;
  import fwvip_wb_pkg::*;
  import fwvip_wb_b2b_targ_tests_pkg::*;

  localparam int ADDR_WIDTH = 32;
  localparam int DATA_WIDTH = 32;
  localparam int SEL_WIDTH  = DATA_WIDTH / 8;

  // ------------------------------------------------------------------
  // Clock / reset
  // ------------------------------------------------------------------
  logic clk;
  logic reset;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  initial begin
    reset = 1'b1;
    repeat (8) @(posedge clk);
    @(negedge clk);
    reset = 1'b0;
  end

  // ------------------------------------------------------------------
  // Wishbone bus
  // ------------------------------------------------------------------
  logic [ADDR_WIDTH-1:0] wb_adr;
  logic                  wb_cyc;
  logic                  wb_stb;
  logic                  wb_we;
  logic                  wb_ack;
  logic                  wb_err;
  logic [SEL_WIDTH-1:0]  wb_sel;
  logic [DATA_WIDTH-1:0] wb_dat_w;
  logic [DATA_WIDTH-1:0] wb_dat_r;

  // ------------------------------------------------------------------
  // BFM instances — target uses REACTIVE=1
  // ------------------------------------------------------------------
  fwvip_wb_initiator_sv #(
    .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
  ) u_initiator (
    .clock(clk),     .reset(reset),
    .adr(wb_adr),    .cyc(wb_cyc),   .stb(wb_stb),
    .we(wb_we),      .ack(wb_ack),   .err(wb_err),
    .sel(wb_sel),    .dat_w(wb_dat_w), .dat_r(wb_dat_r)
  );

  fwvip_wb_target_sv #(
    .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
    .REACTIVE(1'b1)
  ) u_target (
    .clock(clk),     .reset(reset),
    .adr(wb_adr),    .cyc(wb_cyc),   .stb(wb_stb),
    .we(wb_we),      .ack(wb_ack),   .err(wb_err),
    .sel(wb_sel),    .dat_w(wb_dat_w), .dat_r(wb_dat_r)
  );

  fwvip_wb_monitor_sv #(
    .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
  ) u_monitor (
    .clock(clk),     .reset(reset),
    .adr(wb_adr),    .cyc(wb_cyc),   .stb(wb_stb),
    .we(wb_we),      .ack(wb_ack),   .err(wb_err),
    .sel(wb_sel),    .dat_w(wb_dat_w), .dat_r(wb_dat_r)
  );

  fwvip_wb_checker #(
    .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
  ) u_checker (
    .clk(clk),       .rst(reset),
    .adr(wb_adr),    .dat_w(wb_dat_w), .sel(wb_sel),
    .cyc(wb_cyc),    .stb(wb_stb),     .we(wb_we),
    .dat_r(wb_dat_r), .ack(wb_ack),    .err(wb_err),
    .rty(1'b0)
  );

  // ------------------------------------------------------------------
  // UVM config setup and test launch
  // ------------------------------------------------------------------
  fwvip_wb_init_cfg_t #(ADDR_WIDTH, DATA_WIDTH) init_cfg;
  fwvip_wb_targ_cfg_t #(ADDR_WIDTH, DATA_WIDTH) targ_cfg;
  fwvip_wb_mon_cfg_t  #(ADDR_WIDTH, DATA_WIDTH) mon_cfg;

  initial begin
    init_cfg = new("init_cfg");
    targ_cfg = new("targ_cfg");
    mon_cfg  = new("mon_cfg");

    init_cfg.vif = u_initiator.bfm_if;
    targ_cfg.vif = u_target.bfm_if;
    mon_cfg.vif  = u_monitor.bfm_if;

    uvm_config_db #(fwvip_wb_init_cfg)::set(
        null, "uvm_test_top.env.init_agent", "cfg", init_cfg);
    uvm_config_db #(fwvip_wb_targ_cfg)::set(
        null, "uvm_test_top.env.targ_agent", "cfg", targ_cfg);
    uvm_config_db #(fwvip_wb_mon_cfg)::set(
        null, "uvm_test_top.env.mon_agent",  "cfg", mon_cfg);

    run_test();
  end

endmodule
