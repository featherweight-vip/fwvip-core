
`ifndef INCLUDED_FWVIP_MACROS_SVH
`define INCLUDED_FWVIP_MACROS_SVH

`define fwvip_path_decl \
    function automatic string path(); \
        string ret = $sformatf("%m"); \
        for (int i=ret.len()-1; i>=0; i--) begin \
            if (ret[i] == ".") begin \
                ret = ret.substr(0, i-1); \
                break; \
            end \
        end \
        return ret; \
    endfunction

`define fwvip_bfm_rgy_decl(library, kind, type) \
    fwvip_pkg::fwvip_rgy #(type) library``_``kind``_rgy;

`define fwvip_bfm_t interface
`define fwvip_bfm_t_end endinterface


`endif /* INCLUDED_FWVIP_MACROS_SVH */