// Visual QA: vvp game_preview.vvp +PAGE=3 +OUT=docs/game_preview.ppm
// PAGE 0=title, 1=instructions, 2=preview, 3=playing.
`timescale 1ns/1ps
module Game_VGA_preview_tb;
    logic clk=0,rst=1;
    wire [3:0] r,g,b;
    wire hs,vs;
    wire [79:0] targets,initials;
    wire [7:0] initial_locked;
    wire [15:0] mids,ends;
    wire [9:0] source_y,goal_y;
    wire [5:0] time_limit;
    logic [1:0] level;
    logic [2:0] state;
    integer page=3,file_handle;
    string output_path;
    always #5 clk=~clk;
    always_comb begin
        level=page==3 ? 2'd3 : 2'd1;
        state=3'(page);
    end
    Game_Level_Config config0(
        .level(level),.time_limit(time_limit),.source_y(source_y),.goal_y(goal_y),
        .target_positions(targets),.initial_positions(initials),
        .initial_locked(initial_locked),.mid_codes(mids),.end_codes(ends)
    );
    Game_VGA video(
        .clk(clk),.rst(rst),.enable(page!=0),
        .state(state),.level(level),.selected(3'd1),
        .seconds_left(page==3 ? 6'd47 : 6'd40),
        .pipe_locked(initial_locked),.pipe_positions(initials),
        .target_positions(targets),.mid_codes(mids),.end_codes(ends),
        .source_y(source_y),.goal_y(goal_y),.pipe_direction(8'b10101010),
        .ball_x(10'd48),.volume_bar(7'b0001111),
        .VGA_R(r),.VGA_G(g),.VGA_B(b),.VGA_HS(hs),.VGA_VS(vs)
    );
    initial begin
        if(!$value$plusargs("PAGE=%d",page)) page=3;
        if(!$value$plusargs("OUT=%s",output_path)) output_path="game_preview.ppm";
        file_handle=$fopen(output_path,"wb");
        if(!file_handle) $fatal(1,"cannot open preview output");
        $fwrite(file_handle,"P6\n640 480\n255\n");
        repeat(3) @(negedge clk);rst=0;
    end
    always @(posedge clk) begin
        if(!rst && video.pixel_phase==2'd3 && video.h<640 && video.v<480) begin
            $fwrite(file_handle,"%c%c%c",r*17,g*17,b*17);
            if(video.h==639 && video.v==479) begin
                $fclose(file_handle);
                $display("Game_VGA_preview_tb wrote %s",output_path);
                $finish;
            end
        end
    end
endmodule
