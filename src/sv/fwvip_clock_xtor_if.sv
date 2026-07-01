
interface fwvip_clock_xtor_if(
    input clock,
    input reset);

    // Advance 'n' clock cycles. Each caller waits independently, so any number
    // of UVM components may share a single clock transactor and call tick().
    task automatic tick(int n);
        repeat (n) @(posedge clock);
    endtask

endinterface
