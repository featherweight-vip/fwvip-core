`include "uvm_macros.svh"

/**
 * fwvip_core_uvm_pkg -- UVM methodology layer for the core transactors.
 *
 * Provides UVM config objects that adapt the signal-level clock/reset
 * transactor interfaces (fwvip_clock_xtor_if / fwvip_reset_xtor_if) to the
 * abstract APIs (fwvip_clock_if / fwvip_wait_reset_if, from fwvip_core_pkg)
 * that components consume out of the config DB.
 */
package fwvip_core_uvm_pkg;
    import uvm_pkg::*;
    // Abstract clock/reset APIs the configs implement.
    import fwvip_core_pkg::*;

    `include "fwvip_clock_config.svh"
    `include "fwvip_reset_config.svh"

endpackage
