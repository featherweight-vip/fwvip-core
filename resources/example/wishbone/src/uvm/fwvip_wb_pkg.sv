`include "uvm_macros.svh"
`include "fwvip_wb_macros.svh"

package fwvip_wb_pkg;
  import uvm_pkg::*;

  // Max widths for unparameterized sequence items and base config classes
  parameter int FWVIP_WB_ADDR_WIDTH_MAX = 32;
  parameter int FWVIP_WB_DATA_WIDTH_MAX = 32;

  // Shared transaction items
  `include "fwvip_wb_seq_item.svh"
  `include "fwvip_wb_mon_item.svh"

  // Initiator agent
  `include "fwvip_wb_init_op_api.svh"
  `include "fwvip_wb_init_cfg.svh"
  `include "fwvip_wb_init_cfg_t.svh"
  `include "fwvip_wb_init_driver.svh"
  `include "fwvip_wb_init_seqr.svh"
  `include "fwvip_wb_init_agent.svh"

  // Target agent
  `include "fwvip_wb_targ_op_api.svh"
  `include "fwvip_wb_targ_cfg.svh"
  `include "fwvip_wb_targ_cfg_t.svh"
  `include "fwvip_wb_targ_driver.svh"
  `include "fwvip_wb_targ_seqr.svh"
  `include "fwvip_wb_targ_agent.svh"

  // Monitor agent
  `include "fwvip_wb_mon_op_api.svh"
  `include "fwvip_wb_mon_cfg.svh"
  `include "fwvip_wb_mon_cfg_t.svh"
  `include "fwvip_wb_monitor.svh"
  `include "fwvip_wb_mon_agent.svh"

endpackage
