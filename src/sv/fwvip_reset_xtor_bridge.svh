
typedef interface class fwvip_reset_if;

class fwvip_reset_xtor_bridge #(type vif_t=int);
    vif_t           m_xtor_if;
    fwvip_reset_if  m_reset_if;

    task start();
        fork
            run();
        join_none
    endtask

    task run();
        bit asserted;
        forever begin
            xtor_if.wait_change(asserted);
            if (m_reset_if != null) begin
                if (asserted) begin
                    m_reset_if.reset_asserted();
                end else begin
                    m_reset_if.reset_deasserted();
                end
            end
        end
    endtask

endclass