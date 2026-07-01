/**
 * fwvip_reset_config -- UVM config object exposing reset state to the env.
 *
 * Components/testbench look this object up out of the config DB and call
 * wait_reset() to block until the design is out of reset. The object
 * implements the fwvip_wait_reset_if API, so consumers depend only on the
 * interface class -- not on the concrete, vif-parameterized specialization.
 *
 * The specialization monitors reset *events* through the reset transactor's
 * wait_change() task. A single background monitor owns that (stateful) edge
 * stream and republishes the current state as a member flag plus a pulsed
 * event, so any number of components may call wait_reset() concurrently
 * without contending for the transactor.
 */
class fwvip_reset_config extends uvm_object
    implements fwvip_wait_reset_if;
    `uvm_object_utils(fwvip_reset_config)

    function new(string name="fwvip_reset_config");
        super.new(name);
    endfunction

    // Default: never in reset. The vif-bearing specialization overrides.
    virtual task wait_reset();
    endtask

endclass

// vif-aware specialization. vif_t is a virtual fwvip_reset_xtor_if#(ACTIVE).
class fwvip_reset_config_p #(type vif_t=int) extends fwvip_reset_config;
    typedef fwvip_reset_config_p #(vif_t) this_t;
    vif_t vif;

    // Published reset state, maintained by the single monitor process.
    protected bit   m_in_reset;   // current reset state (1 == asserted)
    protected bit   m_sampled;    // monitor has observed state at least once
    protected bit   m_running;    // monitor process has been forked
    protected event m_change;     // pulsed on every observed reset transition

    static function void set(uvm_component ctxt, string inst, string field, vif_t vif);
        this_t cfg = new();
        cfg.vif = vif;
        uvm_config_db #(fwvip_reset_config)::set(ctxt, inst, field, cfg);
    endfunction

    // Single owner of the transactor's stateful wait_change() stream. The
    // first wait_change() returns the current state immediately, so m_sampled
    // becomes valid without needing an actual edge.
    protected task run();
        bit asserted;
        forever begin
            vif.wait_change(asserted);
            m_in_reset = asserted;
            m_sampled  = 1;
            -> m_change;
        end
    endtask

    // Block until the design is out of reset. Lazily starts the monitor on the
    // first call so consumers only ever need to "look up the config and call
    // wait_reset()". The m_running guard is set before any blocking statement,
    // so concurrent first-callers cannot double-fork the monitor.
    virtual task wait_reset();
        if (!m_running) begin
            m_running = 1;
            fork
                run();
            join_none
        end
        wait (m_sampled);
        while (m_in_reset) @(m_change);
    endtask

endclass
