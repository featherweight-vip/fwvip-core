/**
 * fwvip_clock_config -- UVM config object exposing a clock transactor.
 *
 * Components in the UVM hierarchy look this object up out of the config DB and
 * call tick() to wait for one (or n) clock 'ticks'. The object implements the
 * fwvip_clock_if API, so consumers depend only on the interface class -- never
 * on the concrete, vif-parameterized specialization below.
 *
 * Because tick() simply waits on the clock edge through the transactor vif,
 * any number of components may share one clock_config and call tick()
 * concurrently; each caller blocks independently.
 */
class fwvip_clock_config extends uvm_object
    implements fwvip_clock_if;
    `uvm_object_utils(fwvip_clock_config)

    function new(string name="fwvip_clock_config");
        super.new(name);
    endfunction

    // Default: no clock connected. The vif-bearing specialization overrides.
    virtual task tick(int n=1);
    endtask

endclass

// Width/vif-aware specialization. vif_t is a virtual fwvip_clock_xtor_if.
class fwvip_clock_config_p #(type vif_t=int) extends fwvip_clock_config;
    typedef fwvip_clock_config_p #(vif_t) this_t;
    vif_t vif;

    // Build the config around 'vif' and register it in the config DB. The DB
    // entry is typed as the base class so lookups stay vif-agnostic.
    static function void set(uvm_component ctxt, string inst, string field, vif_t vif);
        this_t cfg = new();
        cfg.vif = vif;
        uvm_config_db #(fwvip_clock_config)::set(ctxt, inst, field, cfg);
    endfunction

    virtual task tick(int n=1);
        vif.tick(n);
    endtask

endclass
