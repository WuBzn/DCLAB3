`timescale 1ns/1ps

module Seven_Segment_Display_tb;
    logic clk = 0, rst = 1;
    logic recording = 0, playing = 0, paused = 0, recorded = 0;
    logic overflow = 0;
    logic [4:0] seconds = 0;
    logic [3:0] speed = 0;
    wire CA, CB, CC, CD, CE, CF, CG, DP;
    wire [7:0] AN;
    wire [6:0] segment = {CG, CF, CE, CD, CC, CB, CA};

    always #5 clk = ~clk;

    Seven_Segment_Display #(.SCAN_TICKS(1)) dut (
        .i_clk(clk), .i_rst(rst),
        .i_recording(recording), .i_playing(playing),
        .i_paused(paused), .i_recorded(recorded),
        .i_overflow(overflow), .i_seconds(seconds), .i_speed(speed),
        .CA(CA), .CB(CB), .CC(CC), .CD(CD), .CE(CE), .CF(CF),
        .CG(CG), .DP(DP), .o_an(AN)
    );

    function automatic [6:0] expected_segments(input [7:0] ch);
        case (ch)
            "0": expected_segments = 7'b1000000;
            "1": expected_segments = 7'b1111001;
            "2": expected_segments = 7'b0100100;
            "3": expected_segments = 7'b0110000;
            "4": expected_segments = 7'b0011001;
            "5": expected_segments = 7'b0010010;
            "6": expected_segments = 7'b0000010;
            "7": expected_segments = 7'b1111000;
            "8": expected_segments = 7'b0000000;
            "9": expected_segments = 7'b0010000;
            "-": expected_segments = 7'b0111111;
            "r": expected_segments = 7'b0101111;
            "E": expected_segments = 7'b0000110;
            "C": expected_segments = 7'b1000110;
            "P": expected_segments = 7'b0001100;
            "L": expected_segments = 7'b1000111;
            "Y": expected_segments = 7'b0010001;
            "A": expected_segments = 7'b0001000;
            "U": expected_segments = 7'b1000001;
            "S": expected_segments = 7'b0010010;
            "t": expected_segments = 7'b0000111;
            "F": expected_segments = 7'b0001110;
            "n": expected_segments = 7'b0101011;
            " ": expected_segments = 7'b1111111;
            default: $fatal(1, "Unexpected expected character %c", ch);
        endcase
    endfunction

    task automatic check_frame(input [63:0] expected_text);
        integer index;
        reg [7:0] ch;
        reg [7:0] expected_an;
        begin
            // At one tick per digit, eight consecutive cycles cover all digits.
            repeat (8) begin
                @(negedge clk);
                index = dut.scan_digit;
                ch = expected_text[index*8 +: 8];
                expected_an = ch == " " ? 8'hff : ~(8'h01 << index);
                if (AN !== expected_an ||
                    segment !== expected_segments(ch) || DP !== 1'b1)
                    $fatal(1, "%s digit %0d: AN=%h seg=%b DP=%b expected %c",
                           expected_text, index, AN, segment, DP, ch);
            end
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 0;
        check_frame("---00---");

        recording = 1;
        seconds = 5;
        check_frame("rEC05---");

        recording = 0;
        recorded = 1;
        playing = 1;
        speed = 3; // 4x
        check_frame("PLY05F04");

        playing = 0;
        paused = 1;
        speed = 11; // 1/4x
        check_frame("PAU05S04");

        paused = 0;
        playing = 1;
        speed = 8; // 1x with SW[3] high
        check_frame("PLY05n01");

        speed = 7; // 8x
        check_frame("PLY05F08");
        speed = 15; // 1/8x
        check_frame("PLY05S08");

        playing = 0;
        seconds = 12;
        check_frame("StP12---");
        seconds = 16;
        check_frame("StP16---");

        overflow = 1;
        check_frame("Err16   ");
        $display("PASS: seven-segment status, time, speed, and scan outputs");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Seven-segment test timed out");
    end
endmodule
