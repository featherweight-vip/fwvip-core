/**
 * fwvip_core_pkg -- methodology-independent core APIs.
 *
 * Holds the abstract interface-class APIs for the core clock/reset
 * transactors. These carry no UVM dependency, so plain-SV testbenches (and the
 * UVM layer in fwvip_core_uvm_pkg) can both consume them.
 */
package fwvip_core_pkg;

    `include "fwvip_clock_if.svh"
    `include "fwvip_reset_if.svh"
    `include "fwvip_wait_reset_if.svh"

endpackage
