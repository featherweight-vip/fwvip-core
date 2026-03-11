`ifndef INCLUDED_FWVIP_WB_MACROS_SVH
`define INCLUDED_FWVIP_WB_MACROS_SVH

`define FWVIP_WB_REQ_STRUCT(ADDR_WIDTH, DATA_WIDTH) \
    struct packed { \
        bit[ADDR_WIDTH - 1:0]   adr; \
        bit[DATA_WIDTH - 1:0]   dat; \
        bit                     we;  \
    }

// Arithmetic width helpers — equivalent to $bits() on the structs above but
// usable in parameter default expressions by Yosys/sby (which cannot evaluate
// $bits() applied to an anonymous struct in that context).
`define FWVIP_WB_REQ_WIDTH(ADDR_WIDTH, DATA_WIDTH) ((ADDR_WIDTH) + (DATA_WIDTH) + 1)
`define FWVIP_WB_RSP_WIDTH(ADDR_WIDTH, DATA_WIDTH) ((DATA_WIDTH) + 1)

`define FWVIP_WB_RSP_STRUCT(ADDR_WIDTH, DATA_WIDTH) \
    struct packed { \
        bit[DATA_WIDTH - 1:0]   dat; \
        bit                     err; \
    }

`define FWVIP_WB_MON_STRUCT(ADDR_WIDTH, DATA_WIDTH) \
    struct packed { \
        bit[ADDR_WIDTH - 1:0]   adr;     \
        bit[DATA_WIDTH - 1:0]   dat;     \
        bit                     err;     \
        bit                     we;      \
        bit[15:0]               cyc_len; \
    }

`define FWVIP_WB_MON_WIDTH(ADDR_WIDTH, DATA_WIDTH) ((ADDR_WIDTH) + (DATA_WIDTH) + 1 + 1 + 16)

`endif /* INCLUDED_FWVIP_WB_MACROS_SVH */

