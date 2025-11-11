`include "fwvip_macros.svh"

/**
 * Ingress FIFO BFM used with a full SV/UVM environment
 */
interface fwvip_ingress_fifo_if #(
        parameter int WIDTH=32
    ) (
        input               clock,
        input               reset,
        output[WIDTH-1:0]   data,
        output              valid,
        input               ready
    );

    task put(reg[WIDTH-1:0]     data);
    endtask

endinterface

