# UVM methodology layer

A Featherweight UVM VIP (`fwvip-<proto>`) is a class-based methodology layer over the
transactor kit. Wishbone (`fwvip-wb`) names are shown as the worked example.

- **Package and width policy**
  - `fwvip_<proto>_pkg` imports `uvm_pkg`, the kit's class layer (`fw_proto_<proto>_pkg`:
    the `<proto>_proto_if` method API + `*_xtor_bridge` classes), and the VIP width package
    `fwvip_<proto>_xtor_pkg`. It includes the transaction, the agents, configs, drivers,
    sequences, and a `uvm_reg_adapter`.
  - The VIP is non-parameterized, so its fields are sized by `ADDR_WIDTH_MAX` /
    `DATA_WIDTH_MAX` (Decision D4 — the consumer owns the max widths, the kit is exact-width
    per instance).
- **Agents per role**
  - `fwvip_<proto>_initiator` and `fwvip_<proto>_target` are `uvm_agent`s with a sequencer +
    role-specific driver; `fwvip_<proto>_monitor_agent` is a passive analysis-port producer.
- **Passing the transactor virtual interface**
  - Each role has an abstract config plus a parameterized subtype
    `*_config_p #(type vif_t, int ADDR_WIDTH, int DATA_WIDTH)` carrying the typed vif handle
    to the kit transactor's `u_if`.
  - A static `set()` places the config in `uvm_config_db` under field `"cfg"`; components
    retrieve it in `build_phase`. The `*_register` macros wrap this call.
  - VIF task APIs: the **initiator** driver calls `request(adr, dat, sel, we)` then
    `response(dat, err)`; the **monitor** calls `wait_txn(adr, dat, sel, we, err)` and
    `wait_reset()`. The **target** does not poll — see below.
- **Target callback model**
  - The kit's `<proto>_target_xtor_bridge` polls the request FIFO and *calls* a method-API
    callback per request. `fwvip_<proto>_target_config_p` implements `<proto>_proto_if`,
    owns the bridge, and `start()`s it. Each request flows
    bridge → `config.access()` → `driver.service()` → sequencer → responder
    `handle_request()`. The responder sequence implements `fwvip_<proto>_target_if` and
    sends a lightweight wrapper item (UVM forbids sending a sequence to `start_item()`).
- **Registration macros**
  - `` `uvm_component_utils `` for agents/drivers; `` `uvm_object_utils `` for
    configs/transactions/adapters. `fwvip_<proto>_<role>_register(AW, DW, vif, inst)` binds a
    transactor `u_if` into the config DB in one line.
- **Register layer**
  - A `uvm_reg_adapter` maps `uvm_reg_bus_op` to the VIP transaction and back (see
    `fwvip_wb_reg_adapter` as a template) for front-door register access.
- **Reset synchronization**
  - The env sources the `fwvip-core` clock/reset config providers (`fwvip_clock_config` /
    `fwvip_reset_config`) and waits on the reset provider before driving stimulus.
