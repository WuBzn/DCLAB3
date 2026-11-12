`timescale 1ns/1ps
module Game_Display_tb;
    logic clk=0, rst=1, enable=1;
    logic [2:0] state=3;
    logic [1:0] level=2;
    logic [2:0] selected=1;
    logic [5:0] seconds_left=47;
    logic [7:0] pipe_locked=8'b1100_1001;
    logic [79:0] pipe_positions={10'd260,10'd260,10'd160,10'd330,
                                  10'd175,10'd330,10'd165,10'd315};
    logic [7:0] pipe_direction=8'b0101_0101;
    wire [79:0] target_positions, initial_positions;
    wire [7:0] initial_locked;
    wire [9:0] source_y, goal_y;
    wire [15:0] mid_codes, end_codes;
    wire [5:0] time_limit;
    wire [79:0] pipe_x_list;
    wire [6:0] pipe_half;
    wire [4:0] tube_half;
    wire [3:0] ball_radius;
    logic [9:0] ball_x=48;
    logic [6:0] volume_bar=7'b0001111;
    wire [3:0] r,g,b;
    wire hs,vs;
    wire CA,CB,CC,CD,CE,CF,CG,DP;
    wire [7:0] AN;
    always #5 clk=~clk;

    Game_Level_Config config0(
        .level(level), .time_limit(time_limit),
        .source_y(source_y), .goal_y(goal_y),
        .target_positions(target_positions),
        .initial_positions(initial_positions),
        .initial_locked(initial_locked),
        .mid_codes(mid_codes), .end_codes(end_codes),
        .pipe_x_list(pipe_x_list), .pipe_half(pipe_half),
        .tube_half(tube_half), .ball_radius(ball_radius)
    );
    Game_VGA video(
        .clk(clk), .rst(rst), .enable(enable),
        .state(state), .level(level), .selected(selected),
        .seconds_left(seconds_left), .pipe_locked(pipe_locked),
        .pipe_positions(pipe_positions), .ball_x(ball_x),
        .volume_bar(volume_bar), .pipe_direction(pipe_direction),
        .source_y(source_y), .goal_y(goal_y),
        .target_positions(target_positions),
        .mid_codes(mid_codes), .end_codes(end_codes),
        .pipe_x_list(pipe_x_list), .pipe_half(pipe_half),
        .tube_half(tube_half), .ball_radius(ball_radius),
        .sensitivity(2'd2),
        .VGA_R(r), .VGA_G(g), .VGA_B(b), .VGA_HS(hs), .VGA_VS(vs)
    );
    Game_SevenSegment #(.SCAN_TICKS(1)) seven(
        .clk(clk), .rst(rst), .level(level),
        .seconds_left(seconds_left), .selected(selected),
        .CA(CA), .CB(CB), .CC(CC), .CD(CD),
        .CE(CE), .CF(CF), .CG(CG), .DP(DP), .AN(AN)
    );

    initial begin
        repeat(3) @(negedge clk);
        rst=0;
        // The rightmost digit should be selected pipe 2, then P, 7, 2.
        repeat(1) @(negedge clk);
        if (AN !== 8'b11111101 || {CG,CF,CE,CD,CC,CB,CA} !== 7'b0001100)
            $fatal(1,"pipe label scan incorrect");
        repeat(1) @(negedge clk);
        if (AN !== 8'b11111011 || {CG,CF,CE,CD,CC,CB,CA} !== 7'b1111000)
            $fatal(1,"seconds units scan incorrect");
        repeat(1) @(negedge clk);
        if (AN !== 8'b11110111 || {CG,CF,CE,CD,CC,CB,CA} !== 7'b0011001)
            $fatal(1,"seconds tens scan incorrect");
        seconds_left=60;
        repeat(8) @(negedge clk);
        if (AN !== 8'b11110111 || {CG,CF,CE,CD,CC,CB,CA} !== 7'b0000010)
            $fatal(1,"60-second scan incorrect");
        // Colour and sync are registered together, one pixel late.
        wait(video.h == 10'd656);
        @(negedge clk);
        if (hs !== 1'b1) $fatal(1,"horizontal sync asserted early");
        wait(video.h == 10'd657);
        @(negedge clk);
        if (hs !== 1'b0) $fatal(1,"horizontal sync did not assert");
        wait(video.h == 10'd753);
        @(negedge clk);
        if (hs !== 1'b1) $fatal(1,"horizontal sync did not deassert");
        wait(video.h == 10'd101);
        @(negedge clk);
        if ({r,g,b} !== video.rgb_q || video.rgb_q === 12'h000)
            $fatal(1,"visible colour is not driven");
        wait(video.v == 10'd1 && video.h == 1);
        @(negedge clk);
        if (vs !== 1'b1) $fatal(1,"vertical sync asserted in visible area");
        force video.v = 10'd490;
        repeat(5) @(negedge clk);
        if (vs !== 1'b0) $fatal(1,"vertical sync did not assert");
        force video.v = 10'd492;
        repeat(5) @(negedge clk);
        if (vs !== 1'b1) $fatal(1,"vertical sync did not deassert");
        release video.v;
        $display("Game_Display_tb PASS");
        $finish;
    end
endmodule
