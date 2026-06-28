
interface fwvip_clock_xtor_if(
    input clock,
    input reset);

    task automatic tick(int n);
    endtask

endinterface
