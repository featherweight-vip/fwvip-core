/**
 * fwvip_wb_checker.sv — Wishbone B.3 Protocol Checker
 *
 * Checks the invariant properties of the Wishbone SoC Interconnection
 * Architecture, Revision B.3 (OpenCores, September 2002).
 *
 * Two implementations are selected by a preprocessor define:
 *
 *   WB_CHECKER_SVA (defined)
 *     Concurrent SVA properties for full-featured simulators.
 *
 *   WB_CHECKER_SVA (not defined, default)
 *     Synthesizable RTL state machines with immediate 'assert' statements.
 *     Compatible with sby (SymbiYosys / Yosys formal).
 *
 * Parameters
 * ----------
 *   ADDR_WIDTH   : Address bus width (default 32)
 *   DATA_WIDTH   : Data bus width (default 32)
 *   CLASSIC_ONLY : 1 = Classic mode only; enforces that ACK/ERR/RTY require
 *                  STB & CYC (RULE 3.35).  Set to 0 for Wishbone Registered
 *                  Feedback mode where PERMISSION 4.20 allows ACK/ERR/RTY
 *                  while STB is negated.
 *
 * Assertion index
 * ---------------
 *   MASTER-side
 *     A1  ASSERT_M_STB_REQUIRES_CYC          stb |-> cyc              (RULE 3.25)
 *     A2  ASSERT_M_RESET_NEGATES_CYC         rst |=> !cyc             (RULE 3.20)
 *     A3  ASSERT_M_RESET_NEGATES_STB         rst |=> !stb             (RULE 3.20)
 *     A4  ASSERT_M_ADR_STABLE_IN_WAIT        stable(adr) in wait      (RULE 3.60)
 *     A5  ASSERT_M_WE_STABLE_IN_WAIT         stable(we)  in wait      (RULE 3.60)
 *     A6  ASSERT_M_SEL_STABLE_IN_WAIT        stable(sel) in wait      (RULE 3.60)
 *     A7  ASSERT_M_WDAT_STABLE_IN_WRITE_WAIT stable(dat_w) write wait (RULE 3.60)
 *
 *   SLAVE-side
 *     A8  ASSERT_S_ACK_REQUIRES_STB_CYC      ack |-> (stb & cyc)  [CLASSIC_ONLY] (RULE 3.35)
 *     A9  ASSERT_S_ERR_REQUIRES_STB_CYC      err |-> (stb & cyc)  [CLASSIC_ONLY] (RULE 3.35)
 *    A10  ASSERT_S_RTY_REQUIRES_STB_CYC      rty |-> (stb & cyc)  [CLASSIC_ONLY] (RULE 3.35)
 *    A11  ASSERT_S_ONE_HOT_TERMINATION       onehot0({ack,err,rty})               (RULE 3.45)
 */
module fwvip_wb_checker #(
    parameter int  ADDR_WIDTH   = 32,
    parameter int  DATA_WIDTH   = 32,
    /* 1 = enforce Classic-mode rules: ACK/ERR/RTY require STB & CYC.
       0 = Registered Feedback mode: ACK/ERR/RTY may precede STB.       */
    parameter bit  CLASSIC_ONLY = 1
) (
    // SYSCON
    input  logic                      clk,
    input  logic                      rst,

    // MASTER-driven signals
    input  logic [ADDR_WIDTH-1:0]     adr,
    input  logic [DATA_WIDTH-1:0]     dat_w,
    input  logic [DATA_WIDTH/8-1:0]   sel,
    input  logic                      cyc,
    input  logic                      stb,
    input  logic                      we,

    // SLAVE-driven signals
    input  logic [DATA_WIDTH-1:0]     dat_r,
    input  logic                      ack,
    input  logic                      err,
    input  logic                      rty
);

    // Bus phase is pending: transaction in flight, no termination yet.
    wire phase_pending = stb && cyc && !ack && !err && !rty;

    // ----------------------------------------------------------------
    // Shadow registers — synthesizable path only.
    // Capture the bus state one cycle earlier so that |=> (next-cycle)
    // properties can be expressed as combinational comparisons on the
    // following clock edge.
    // ----------------------------------------------------------------
`ifndef WB_CHECKER_SVA
    logic                    rst_d;           // was rst asserted last cycle?
    logic                    phase_pending_d; // was a wait-state in progress?
    logic                    phase_write_d;   // was a write wait-state in progress?
    logic [ADDR_WIDTH-1:0]   adr_d;
    logic [DATA_WIDTH/8-1:0] sel_d;
    logic                    we_d;
    logic [DATA_WIDTH-1:0]   dat_w_d;

    always_ff @(posedge clk) begin
        rst_d           <= rst;
        phase_pending_d <= phase_pending;
        phase_write_d   <= phase_pending && we;
        adr_d           <= adr;
        sel_d           <= sel;
        we_d            <= we;
        dat_w_d         <= dat_w;
    end
`endif

    // ================================================================
    // A1 — STB requires CYC  (RULE 3.25)
    //
    // MASTER interfaces MUST assert [CYC_O] no later than the rising
    // edge that qualifies the assertion of [STB_O].
    //   Property:  stb |-> cyc
    // ================================================================
`ifdef WB_CHECKER_SVA
    ASSERT_M_STB_REQUIRES_CYC :
    assert property (
        @(posedge clk) disable iff (rst)
        stb |-> cyc
    ) else $error("WB CHECKER A1: STB asserted without CYC (RULE 3.25)");
`else
    always_ff @(posedge clk) begin
        if (!rst) begin
            ASSERT_M_STB_REQUIRES_CYC:
                assert (!stb || cyc);
        end
    end
`endif

    // ================================================================
    // A2 — CYC negated after reset  (RULE 3.20)
    //
    // [CYC_O] MUST be negated at the rising [CLK_I] edge following the
    // assertion of [RST_I] and stay negated until [RST_I] is negated.
    //   Property:  rst |=> !cyc
    // ================================================================
`ifdef WB_CHECKER_SVA
    ASSERT_M_RESET_NEGATES_CYC :
    assert property (
        @(posedge clk)
        rst |=> !cyc
    ) else $error("WB CHECKER A2: CYC not negated after RST (RULE 3.20)");
`else
    // rst_d captures "reset was active last cycle"; CYC must be 0 now.
    always_ff @(posedge clk) begin
        if (rst_d) begin
            ASSERT_M_RESET_NEGATES_CYC:
                assert (!cyc);
        end
    end
`endif

    // ================================================================
    // A3 — STB negated after reset  (RULE 3.20)
    //
    //   Property:  rst |=> !stb
    // ================================================================
`ifdef WB_CHECKER_SVA
    ASSERT_M_RESET_NEGATES_STB :
    assert property (
        @(posedge clk)
        rst |=> !stb
    ) else $error("WB CHECKER A3: STB not negated after RST (RULE 3.20)");
`else
    always_ff @(posedge clk) begin
        if (rst_d) begin
            ASSERT_M_RESET_NEGATES_STB:
                assert (!stb);
        end
    end
`endif

    // ================================================================
    // A4 — ADR stable during wait states  (RULE 3.60)
    //
    // MASTER MUST qualify [ADR_O] with [STB_O]: the address must not
    // change while waiting for a cycle-termination signal.
    //   Property:  phase_pending |=> $stable(adr)
    // ================================================================
`ifdef WB_CHECKER_SVA
    ASSERT_M_ADR_STABLE_IN_WAIT :
    assert property (
        @(posedge clk) disable iff (rst)
        phase_pending |=> $stable(adr)
    ) else $error("WB CHECKER A4: ADR changed during wait state (RULE 3.60)");
`else
    // phase_pending_d: "a wait-state was in progress last cycle".
    // If so, adr must equal the registered copy from that cycle.
    always_ff @(posedge clk) begin
        if (!rst && phase_pending_d) begin
            ASSERT_M_ADR_STABLE_IN_WAIT:
                assert (adr == adr_d);
        end
    end
`endif

    // ================================================================
    // A5 — WE stable during wait states  (RULE 3.60)
    //
    //   Property:  phase_pending |=> $stable(we)
    // ================================================================
`ifdef WB_CHECKER_SVA
    ASSERT_M_WE_STABLE_IN_WAIT :
    assert property (
        @(posedge clk) disable iff (rst)
        phase_pending |=> $stable(we)
    ) else $error("WB CHECKER A5: WE changed during wait state (RULE 3.60)");
`else
    always_ff @(posedge clk) begin
        if (!rst && phase_pending_d) begin
            ASSERT_M_WE_STABLE_IN_WAIT:
                assert (we == we_d);
        end
    end
`endif

    // ================================================================
    // A6 — SEL stable during wait states  (RULE 3.60)
    //
    //   Property:  phase_pending |=> $stable(sel)
    // ================================================================
`ifdef WB_CHECKER_SVA
    ASSERT_M_SEL_STABLE_IN_WAIT :
    assert property (
        @(posedge clk) disable iff (rst)
        phase_pending |=> $stable(sel)
    ) else $error("WB CHECKER A6: SEL changed during wait state (RULE 3.60)");
`else
    always_ff @(posedge clk) begin
        if (!rst && phase_pending_d) begin
            ASSERT_M_SEL_STABLE_IN_WAIT:
                assert (sel == sel_d);
        end
    end
`endif

    // ================================================================
    // A7 — DAT_W stable during write wait states  (RULE 3.60)
    //
    // Write data must not change while waiting for ACK on a WRITE cycle.
    //   Property:  (phase_pending && we) |=> $stable(dat_w)
    // ================================================================
`ifdef WB_CHECKER_SVA
    ASSERT_M_WDAT_STABLE_IN_WRITE_WAIT :
    assert property (
        @(posedge clk) disable iff (rst)
        (phase_pending && we) |=> $stable(dat_w)
    ) else $error("WB CHECKER A7: DAT_W changed during write wait state (RULE 3.60)");
`else
    // phase_write_d: "a write wait-state was in progress last cycle".
    always_ff @(posedge clk) begin
        if (!rst && phase_write_d) begin
            ASSERT_M_WDAT_STABLE_IN_WRITE_WAIT:
                assert (dat_w == dat_w_d);
        end
    end
`endif

    // ================================================================
    // A8-A10 — Termination signals require STB & CYC  (RULE 3.35)
    //          Classic mode only (CLASSIC_ONLY parameter).
    //
    // Cycle termination signals MUST be generated in response to the
    // logical AND of [CYC_I] and [STB_I].
    //   Property:  ack/err/rty |-> (stb && cyc)
    // ================================================================
    if (CLASSIC_ONLY) begin : gen_classic_checks
`ifdef WB_CHECKER_SVA
        ASSERT_S_ACK_REQUIRES_STB_CYC :
        assert property (
            @(posedge clk) disable iff (rst)
            ack |-> (stb && cyc)
        ) else $error("WB CHECKER A8: ACK without STB & CYC (RULE 3.35)");

        ASSERT_S_ERR_REQUIRES_STB_CYC :
        assert property (
            @(posedge clk) disable iff (rst)
            err |-> (stb && cyc)
        ) else $error("WB CHECKER A9: ERR without STB & CYC (RULE 3.35)");

        ASSERT_S_RTY_REQUIRES_STB_CYC :
        assert property (
            @(posedge clk) disable iff (rst)
            rty |-> (stb && cyc)
        ) else $error("WB CHECKER A10: RTY without STB & CYC (RULE 3.35)");
`else
        always_ff @(posedge clk) begin
            if (!rst) begin
                ASSERT_S_ACK_REQUIRES_STB_CYC:
                    assert (!ack || (stb && cyc));

                ASSERT_S_ERR_REQUIRES_STB_CYC:
                    assert (!err || (stb && cyc));

                ASSERT_S_RTY_REQUIRES_STB_CYC:
                    assert (!rty || (stb && cyc));
            end
        end
`endif
    end

    // ================================================================
    // A11 — At most one termination signal at a time  (RULE 3.45)
    //
    // SLAVE MUST NOT assert more than one of [ACK_O], [ERR_O], [RTY_O]
    // simultaneously.
    //   Property:  $onehot0({ack, err, rty})
    // ================================================================
`ifdef WB_CHECKER_SVA
    ASSERT_S_ONE_HOT_TERMINATION :
    assert property (
        @(posedge clk) disable iff (rst)
        $onehot0({ack, err, rty})
    ) else $error("WB CHECKER A11: Multiple termination signals asserted (RULE 3.45)");
`else
    // Expressed as explicit mutual-exclusion to avoid $onehot0 in
    // synthesizable/Yosys context.
    always_ff @(posedge clk) begin
        if (!rst) begin
            ASSERT_S_ONE_HOT_TERMINATION:
                assert (!(ack && err) && !(ack && rty) && !(err && rty));
        end
    end
`endif

endmodule
