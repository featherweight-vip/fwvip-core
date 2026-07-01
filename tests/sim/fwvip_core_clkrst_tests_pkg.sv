/**
 * fwvip_core_clkrst_tests_pkg -- UVM tests for the core clock/reset configs.
 *
 * Exercises:
 *   - fwvip_reset_config.wait_reset(): a component blocks until the design is
 *     out of reset, and the call returns only after reset has de-asserted.
 *   - fwvip_clock_config.tick(): advancing n cycles consumes exactly n clock
 *     periods of simulation time.
 *   - Sharing: several components look the same clock/reset configs up out of
 *     the config DB and each observe identical tick counts -- proving one
 *     transactor can fan out to the whole UVM hierarchy.
 */
package fwvip_core_clkrst_tests_pkg;
    import uvm_pkg::*;
    import fwvip_core_pkg::*;       // abstract clock/reset APIs
    import fwvip_core_uvm_pkg::*;   // clock/reset config objects
    `include "uvm_macros.svh"

    // TB facts the checks rely on (must match clkrst_uvm_tb). The checks below
    // measure the clock period at runtime (via tick()) rather than hard-coding
    // time-unit literals, so they are independent of the compiled timescale.
    parameter int RESET_CYCLES = 5;   // posedges reset is held in the TB

    // ------------------------------------------------------------------
    // A passive component that shares the clock/reset configs and simply
    // counts clock ticks once the design is out of reset.
    // ------------------------------------------------------------------
    class fwvip_core_tick_monitor extends uvm_component;
        `uvm_component_utils(fwvip_core_tick_monitor)

        fwvip_clock_if      m_clk;
        fwvip_wait_reset_if m_rst;
        int unsigned        m_ticks;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            fwvip_clock_config clk_cfg;
            fwvip_reset_config rst_cfg;
            super.build_phase(phase);
            if (!uvm_config_db #(fwvip_clock_config)::get(this, "", "clock", clk_cfg))
                `uvm_fatal(get_type_name(), "no clock config in DB")
            if (!uvm_config_db #(fwvip_reset_config)::get(this, "", "reset", rst_cfg))
                `uvm_fatal(get_type_name(), "no reset config in DB")
            // Hold only the abstract interface-class handles.
            m_clk = clk_cfg;
            m_rst = rst_cfg;
        endfunction

        task run_phase(uvm_phase phase);
            m_rst.wait_reset();
            forever begin
                m_clk.tick();
                m_ticks++;
            end
        endtask
    endclass

    // ------------------------------------------------------------------
    // Directed self-checking test.
    // ------------------------------------------------------------------
    class fwvip_core_clkrst_test extends uvm_test;
        `uvm_component_utils(fwvip_core_clkrst_test)

        localparam int NUM_MON   = 3;
        localparam int TEST_TICKS = 60;

        fwvip_clock_config      m_clk_cfg;
        fwvip_reset_config      m_rst_cfg;
        fwvip_core_tick_monitor m_mon[NUM_MON];

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(fwvip_clock_config)::get(this, "", "clock", m_clk_cfg))
                `uvm_fatal(get_type_name(), "no clock config in DB")
            if (!uvm_config_db #(fwvip_reset_config)::get(this, "", "reset", m_rst_cfg))
                `uvm_fatal(get_type_name(), "no reset config in DB")
            foreach (m_mon[i])
                m_mon[i] = fwvip_core_tick_monitor::type_id::create(
                    $sformatf("mon%0d", i), this);
        endfunction

        task run_phase(uvm_phase phase);
            time t_rst, t0, t1, period;
            phase.raise_objection(this);

            // --- 1. wait_reset() returns only after reset de-asserts ---
            // The call must block through the whole reset interval (it cannot
            // return at time 0).
            m_rst_cfg.wait_reset();
            t_rst = $time;

            // Measure the clock period in raw time units so the remaining
            // checks are timescale-independent.
            t0 = $time;
            m_clk_cfg.tick(1);
            period = $time - t0;

            // wait_reset() should have returned around the reset-deassert point
            // (RESET_CYCLES cycles in, plus up to a cycle of monitor latency),
            // and definitely not at time 0.
            if (t_rst < RESET_CYCLES * period)
                `uvm_error(get_type_name(), $sformatf(
                    "wait_reset() returned at %0t, before reset de-assert (~%0t)",
                    t_rst, RESET_CYCLES * period))
            else if (t_rst > (RESET_CYCLES + 3) * period)
                `uvm_error(get_type_name(), $sformatf(
                    "wait_reset() returned late at %0t (expected ~%0t)",
                    t_rst, RESET_CYCLES * period))
            else
                `uvm_info(get_type_name(), $sformatf(
                    "wait_reset() returned out-of-reset at %0t (period=%0t)",
                    t_rst, period), UVM_LOW)

            // --- 2. tick(n) consumes exactly n clock periods ---
            t0 = $time;
            m_clk_cfg.tick(TEST_TICKS);
            t1 = $time;
            if ((t1 - t0) != TEST_TICKS * period)
                `uvm_error(get_type_name(), $sformatf(
                    "tick(%0d) advanced %0t, expected %0t",
                    TEST_TICKS, t1 - t0, TEST_TICKS * period))
            else
                `uvm_info(get_type_name(), $sformatf(
                    "tick(%0d) advanced exactly %0t (period=%0t)",
                    TEST_TICKS, t1 - t0, period), UVM_LOW)

            // --- 3. every shared monitor observed the same tick count ---
            // The monitors started counting when wait_reset() returned (the same
            // instant for all of them, since they share one reset config), then
            // saw the 1 + TEST_TICKS ticks the test drove on the shared clock.
            #1;  // settle: let any same-edge increments complete
            foreach (m_mon[i]) begin
                if (m_mon[i].m_ticks != TEST_TICKS + 1)
                    `uvm_error(get_type_name(), $sformatf(
                        "mon%0d counted %0d ticks, expected %0d",
                        i, m_mon[i].m_ticks, TEST_TICKS + 1))
                else
                    `uvm_info(get_type_name(), $sformatf(
                        "mon%0d observed %0d shared ticks", i, m_mon[i].m_ticks),
                        UVM_LOW)
            end

            phase.drop_objection(this);
        endtask

        function void report_phase(uvm_phase phase);
            uvm_report_server svr = uvm_report_server::get_server();
            super.report_phase(phase);
            if (svr.get_severity_count(UVM_ERROR) == 0 &&
                svr.get_severity_count(UVM_FATAL) == 0)
                `uvm_info(get_type_name(), "ALL TESTS PASSED", UVM_NONE)
            else
                `uvm_info(get_type_name(), "TEST(S) FAILED", UVM_NONE)
        endfunction
    endclass

endpackage
