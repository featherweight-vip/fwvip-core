
`timescale 1ns/1ps
package fwvip_pkg;

typedef enum {
    BfmKind_Initiator
} bfm_kind_e;

class fwvip_bfm_base;
    bfm_kind_e      kind;
    string          tname;
    string          iname;

    function new(
        bfm_kind_e      kind,
        string          tname,
        string          iname);
        this.kind = kind;
        this.tname = tname;
        this.iname = iname;
    endfunction

endclass

class fwvip_rgy #(type T=int);
    static T      prv_api_m[string];
    static T      prv_api_l[$];

    static function void register(T api);
        prv_api_m[api.path] = api;
        prv_api_l.push_back(api);
    endfunction

    static function T get(
        string          path,
        bit             suffix);
        T ret;;
        if (suffix) begin
            foreach (prv_api_l[i]) begin
                string bfm_path = prv_api_l[i].path;
                if (path.len() <= bfm_path.len()) begin
                    int x;
                    for (x=0; x<path.len(); x++) begin
                        if (path[path.len()-x-1] != bfm_path[bfm_path.len()-x-1]) begin
                            break;
                        end
                    end
                    if (x == path.len()) begin
                        ret = prv_api_l[i];
                        break;
                    end
                end
            end
        end else if (prv_api_m.exists(path)) begin
            ret = prv_api_m[path];
        end
        return ret;
    endfunction
endclass

interface class fwvip_mem_api;

    pure virtual task read8(
        output bit[7:0]     data,
        input bit[63:0]     addr);

    pure virtual task read16(
        output bit[15:0]    data,
        input bit[63:0]     addr);

    pure virtual task read32(
        output bit[31:0]    data,
        input bit[63:0]     addr);

    pure virtual task read64(
        output bit[63:0]    data,
        input bit[63:0]     addr);

    pure virtual task write8(
        input bit[7:0]      data,
        input bit[63:0]     addr);

    pure virtual task write16(
        input bit[15:0]     data,
        input bit[63:0]     addr);

    pure virtual task write32(
        input bit[31:0]     data,
        input bit[63:0]     addr);

    pure virtual task write64(
        input bit[63:0]    data,
        input bit[63:0]     addr);


endclass



endpackage
