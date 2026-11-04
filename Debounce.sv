module Debounce #(
    parameter int CNT_N = 31_250  // 10 ms at 3.125 MHz
)(
    input  i_in,
    input  i_clk,
    input  i_rst,
    output logic o_debounced,
    output logic o_neg,
    output logic o_pos
);
    localparam int COUNT_BITS = $clog2(CNT_N + 1);
    logic sync_0, sync_1;
    logic [COUNT_BITS-1:0] count;

    always_ff @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            sync_0 <= 0;
            sync_1 <= 0;
            count <= 0;
            o_debounced <= 0;
            o_neg <= 0;
            o_pos <= 0;
        end else begin
            sync_0 <= i_in;
            sync_1 <= sync_0;
            o_neg <= 0;
            o_pos <= 0;
            if (sync_1 == o_debounced) begin
                count <= 0;
            end else if (count == CNT_N - 1) begin
                count <= 0;
                o_debounced <= sync_1;
                o_pos <= sync_1;
                o_neg <= !sync_1;
            end else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule
