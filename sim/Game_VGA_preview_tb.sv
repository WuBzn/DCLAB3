// Visual QA: vvp game_preview.vvp +PAGE=3 +OUT=docs/game_preview.ppm
// PAGE 0=title, 1=instructions, 2=level-1 preview, 3=level-3 play,
//      4=level-1 play, 5=level-2 play, 6=level-1 clear, 7=level-2 time up.
// +ANIM=n freezes the demo animation.
`timescale 1ns/1ps
module Game_VGA_preview_tb;
    logic clk=0,rst=1;
    wire [3:0] r,g,b;
    wire hs,vs;
    wire [79:0] targets,initials,xlist;
    wire [7:0] initial_locked;
    wire [15:0] mids,ends;
    wire [9:0] source_y,goal_y;
    wire [5:0] time_limit;
    wire [6:0] half;
    wire [4:0] tube;
    wire [3:0] ball_r;
    logic [1:0] level;
    logic [2:0] state;
    logic [79:0] positions;
    logic [7:0] locked;
    integer page=3,anim_value=40,file_handle;
    string output_path;
    always #5 clk=~clk;
    always_comb begin
        case(page)
            2: begin level=2'd1; state=3'd2; end
            3: begin level=2'd3; state=3'd3; end
            4: begin level=2'd1; state=3'd3; end
            5: begin level=2'd2; state=3'd3; end
            6: begin level=2'd1; state=3'd5; end
            7: begin level=2'd2; state=3'd6; end
            default: begin level=2'd1; state=3'(page); end
        endcase
        // The leftmost pipe is already aligned in the play pages.
        positions=initials;
        locked=initial_locked;
        if(page>=3) begin
            positions[9:0]=targets[9:0];
            locked[0]=1'b1;
        end
        if(page==6) begin
            positions=targets;
            locked=8'hff;
        end
    end
    Game_Level_Config config0(
        .level(level),.time_limit(time_limit),.source_y(source_y),.goal_y(goal_y),
        .target_positions(targets),.initial_positions(initials),
        .initial_locked(initial_locked),.mid_codes(mids),.end_codes(ends),
        .pipe_x_list(xlist),.pipe_half(half),.tube_half(tube),.ball_radius(ball_r)
    );
    Game_VGA video(
        .clk(clk),.rst(rst),.enable(page!=0),
        .state(state),.level(level),.selected(3'd1),
        .seconds_left(page==7 ? 6'd0 : page>=3 ? 6'd47 : time_limit),
        .pipe_locked(locked),.pipe_positions(positions),
        .target_positions(targets),.mid_codes(mids),.end_codes(ends),
        .source_y(source_y),.goal_y(goal_y),.pipe_direction(8'b10101010),
        .ball_x(page==6 ? 10'd600 : 10'd48),.volume_bar(7'b0001111),
        .pipe_x_list(xlist),.pipe_half(half),.tube_half(tube),
        .ball_radius(ball_r),.sensitivity(2'd0),
        .VGA_R(r),.VGA_G(g),.VGA_B(b),.VGA_HS(hs),.VGA_VS(vs)
    );
    initial begin
        if(!$value$plusargs("PAGE=%d",page)) page=3;
        if(!$value$plusargs("ANIM=%d",anim_value)) anim_value=40;
        if(!$value$plusargs("OUT=%s",output_path)) output_path="game_preview.ppm";
        file_handle=$fopen(output_path,"wb");
        if(!file_handle) $fatal(1,"cannot open preview output");
        $fwrite(file_handle,"P6\n640 480\n255\n");
        repeat(3) @(negedge clk);rst=0;
        force video.anim=7'(anim_value);
    end
    // Write the combinational colour of each visible pixel (the output
    // register only delays it by one pixel).
    always @(posedge clk) begin
        if(!rst && video.pixel_phase==2'd3 && video.h<640 && video.v<480) begin
            $fwrite(file_handle,"%c%c%c",video.rgb[11:8]*17,video.rgb[7:4]*17,
                    video.rgb[3:0]*17);
            if(video.h==639 && video.v==479) begin
                $fclose(file_handle);
                $display("Game_VGA_preview_tb wrote %s",output_path);
                $finish;
            end
        end
    end
endmodule
