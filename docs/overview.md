Featherweight VIP (FWVIP) essentials

- The protocol core implements bus semantics once, independent of methodology.
- The core exposes two FIFO-like channels using ready/valid vectors: a request channel into the core and a response channel out of the core.
- A methodology-specific module wraps the core and provides these FIFOs using native primitives (for example, SystemVerilog tasks/queues, UVM components, or DPI shims).
- Roles are split cleanly: initiator, target, and monitor. Each role has a core and (optionally) a methodology wrapper.
- The Wishbone VIP example provides fwvip_wb_initiator_core and fwvip_wb_target_core using request/response channels, and BFMs that connect these cores to a virtual interface.
