Transactor / Bus Functional Model structure

- Core
  - Initiator core: fwvip_wb_initiator_core with RV target port req_ and RV initiator port rsp_; drives Wishbone master signals; single outstanding transfer; simple IDLE/BUS/RESP FSM.
  - Target core: fwvip_wb_target_core with RV initiator port req_ and RV target port rsp_; observes Wishbone slave signals, emits a request, accepts a response, then asserts ACK/ERR.
  - Request vector packs adr, dat_w, byte-enables, we; response vector packs dat_r, err.
- Methodology wrapper
  - Driver BFM: fwvip_wb_driver_bfm binds to the protocol interface, implements configure(), initiate_and_get_response(), respond_and_wait_for_next_transfer(); bridges between transaction structs and pins; proxies to a UVM driver.
  - Monitor BFM: fwvip_wb_monitor_bfm provides start_monitoring() and do_monitor(); captures a transaction struct and notifies the UVM monitor via a proxy callback.
- Monitor role is always passive and never drives pins.
