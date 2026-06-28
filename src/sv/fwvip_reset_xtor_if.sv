
interface fwvip_reset_xtor_if #(
    parameter int ACTIVE=1
) (
    input clock,
    input reset
);
    bit first = 1;

    task automatic wait_change(output bit asserted);
        bit state = reset;
        do begin
            @(posedge clock);
        end while (reset == state && !first);
        first = 0;

        asserted = (reset == ACTIVE);
    endtask

endinterface
