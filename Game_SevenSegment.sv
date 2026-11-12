// L1  40P1: level, seconds left, selected pipe.
module Game_SevenSegment #(
    parameter int SCAN_TICKS = 20_000
)(
    input  logic       clk,
    input  logic       rst,
    input  logic [1:0] level,
    input  logic [5:0] seconds_left,
    input  logic [2:0] selected,
    output logic       CA, CB, CC, CD, CE, CF, CG, DP,
    output logic [7:0] AN
);
    localparam logic [3:0] BLANK=4'd10, LETTER_L=4'd11, LETTER_P=4'd12;
    localparam int COUNT_BITS = $clog2(SCAN_TICKS + 1);
    logic [COUNT_BITS-1:0] scan_count;
    logic [2:0] scan_digit;
    logic [3:0] digit [0:7];
    logic [3:0] tens, ones;

    always_comb begin
        if (seconds_left >= 6'd60) begin
            tens = 4'd6;
            ones = seconds_left - 6'd60;
        end else if (seconds_left >= 6'd50) begin
            tens = 4'd5;
            ones = seconds_left - 6'd50;
        end else if (seconds_left >= 6'd40) begin
            tens = 4'd4;
            ones = seconds_left - 6'd40;
        end else if (seconds_left >= 6'd30) begin
            tens = 4'd3;
            ones = seconds_left - 6'd30;
        end else if (seconds_left >= 6'd20) begin
            tens = 4'd2;
            ones = seconds_left - 6'd20;
        end else if (seconds_left >= 6'd10) begin
            tens = 4'd1;
            ones = seconds_left - 6'd10;
        end else begin
            tens = 4'd0;
            ones = seconds_left[3:0];
        end
        digit[7] = LETTER_L;
        digit[6] = {2'b00, level};
        digit[5] = BLANK;
        digit[4] = BLANK;
        digit[3] = tens;
        digit[2] = ones;
        digit[1] = LETTER_P;
        digit[0] = {1'b0, selected} + 4'd1;
    end

    function automatic logic [6:0] segments(input logic [3:0] value);
        case (value)
            4'd0: segments = 7'b1000000;
            4'd1: segments = 7'b1111001;
            4'd2: segments = 7'b0100100;
            4'd3: segments = 7'b0110000;
            4'd4: segments = 7'b0011001;
            4'd5: segments = 7'b0010010;
            4'd6: segments = 7'b0000010;
            4'd7: segments = 7'b1111000;
            4'd8: segments = 7'b0000000;
            4'd9: segments = 7'b0010000;
            LETTER_L: segments = 7'b1000111;
            LETTER_P: segments = 7'b0001100;
            default: segments = 7'b1111111;
        endcase
    endfunction

    assign DP = 1'b1;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scan_count <= 0;
            scan_digit <= 0;
        end else if (scan_count == SCAN_TICKS - 1) begin
            scan_count <= 0;
            scan_digit <= scan_digit + 1'b1;
        end else begin
            scan_count <= scan_count + 1'b1;
        end
    end

    always_comb begin
        {CG, CF, CE, CD, CC, CB, CA} = segments(digit[scan_digit]);
        AN = 8'hff;
        if (digit[scan_digit] != BLANK)
            AN[scan_digit] = 1'b0;
    end
endmodule
