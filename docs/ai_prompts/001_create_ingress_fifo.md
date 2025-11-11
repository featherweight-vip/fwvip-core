
# Prompt

Implement a WIDTH-width FIFO in fwvip_ingress_fifo_if.sv with a depth of DEPTH. The FIFO must be synchronous. - It must assert `valid` whenever data is available
- It must move to the next item whenever `valid` and `ready` are active
- The `put` method must wait for space to be available in the FIFO before inserting it
