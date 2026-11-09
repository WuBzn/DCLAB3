// Eight-digit, active-low display on the Nexys A7. Reading left to right:
// status (3 digits), source-audio seconds (2), playback rate (3).
// F04 means 4x, S04 means 1/4x, and n01 means normal speed.
module Seven_Segment_Display #(
    parameter int SCAN_TICKS = 1001
)(
    input  logic       i_clk,
    input  logic       i_rst,
    input  logic       i_recording,
    input  logic       i_playing,
    input  logic       i_paused,
    input  logic       i_recorded,
    input  logic       i_overflow,
    input  logic [4:0] i_seconds,
    input  logic [3:0] i_speed,
    output logic       CA, CB, CC, CD, CE, CF, CG, DP,
    output logic [7:0] o_an
);
    localparam logic [4:0]
        BLANK = 5'd10, DASH = 5'd11, LETTER_r = 5'd12,
        LETTER_E = 5'd13, LETTER_C = 5'd14, LETTER_P = 5'd15,
        LETTER_L = 5'd16, LETTER_Y = 5'd17, LETTER_A = 5'd18,
        LETTER_U = 5'd19, LETTER_S = 5'd20, LETTER_t = 5'd21,
        LETTER_F = 5'd22, LETTER_n = 5'd23;

    logic [4:0] glyph [0:7];
    logic [2:0] scan_digit;
    logic [9:0] scan_count;
    logic [3:0] factor;

    assign factor = {1'b0, i_speed[2:0]} + 4'd1;
    assign DP = 1'b1; // Decimal point is not used (active low).

    always_comb begin
        for (integer i = 0; i < 8; i = i + 1)
            glyph[i] = BLANK;

        // The two decimal digits always show the original audio position.
        glyph[4] = i_seconds >= 5'd10 ? 5'd1 : 5'd0;
        glyph[3] = i_seconds >= 5'd10 ? i_seconds - 5'd10 : i_seconds;

        if (i_overflow) begin
            glyph[7] = LETTER_E;
            glyph[6] = LETTER_r;
            glyph[5] = LETTER_r;
        end else if (i_recording) begin
            glyph[7] = LETTER_r;
            glyph[6] = LETTER_E;
            glyph[5] = LETTER_C;
            glyph[2] = DASH;
            glyph[1] = DASH;
            glyph[0] = DASH;
        end else if (i_playing || i_paused) begin
            glyph[7] = LETTER_P;
            glyph[6] = i_paused ? LETTER_A : LETTER_L;
            glyph[5] = i_paused ? LETTER_U : LETTER_Y;
            glyph[2] = factor == 4'd1 ? LETTER_n :
                       i_speed[3] ? LETTER_S : LETTER_F;
            glyph[1] = 5'd0;
            glyph[0] = {1'b0, factor};
        end else if (i_recorded) begin
            glyph[7] = LETTER_S;
            glyph[6] = LETTER_t;
            glyph[5] = LETTER_P;
            glyph[2] = DASH;
            glyph[1] = DASH;
            glyph[0] = DASH;
        end else begin
            glyph[7] = DASH;
            glyph[6] = DASH;
            glyph[5] = DASH;
            glyph[2] = DASH;
            glyph[1] = DASH;
            glyph[0] = DASH;
        end
    end

    // Segment order is {CG, CF, CE, CD, CC, CB, CA}; zero turns a segment on.
    function automatic logic [6:0] segments(input logic [4:0] value);
        case (value)
            5'd0:     segments = 7'b1000000;
            5'd1:     segments = 7'b1111001;
            5'd2:     segments = 7'b0100100;
            5'd3:     segments = 7'b0110000;
            5'd4:     segments = 7'b0011001;
            5'd5:     segments = 7'b0010010;
            5'd6:     segments = 7'b0000010;
            5'd7:     segments = 7'b1111000;
            5'd8:     segments = 7'b0000000;
            5'd9:     segments = 7'b0010000;
            DASH:     segments = 7'b0111111;
            LETTER_r: segments = 7'b0101111;
            LETTER_E: segments = 7'b0000110;
            LETTER_C: segments = 7'b1000110;
            LETTER_P: segments = 7'b0001100;
            LETTER_L: segments = 7'b1000111;
            LETTER_Y: segments = 7'b0010001;
            LETTER_A: segments = 7'b0001000;
            LETTER_U: segments = 7'b1000001;
            LETTER_S: segments = 7'b0010010;
            LETTER_t: segments = 7'b0000111;
            LETTER_F: segments = 7'b0001110;
            LETTER_n: segments = 7'b0101011;
            default:  segments = 7'b1111111;
        endcase
    endfunction

    always_ff @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            scan_digit <= 3'd0;
            scan_count <= 10'd0;
        end else if (scan_count == SCAN_TICKS - 1) begin
            scan_count <= 10'd0;
            scan_digit <= scan_digit + 1'b1;
        end else begin
            scan_count <= scan_count + 1'b1;
        end
    end

    always_comb begin
        {CG, CF, CE, CD, CC, CB, CA} = segments(glyph[scan_digit]);
        o_an = 8'hff;
        if (glyph[scan_digit] != BLANK)
            o_an[scan_digit] = 1'b0;
    end
endmodule
