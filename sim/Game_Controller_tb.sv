`timescale 1ns/1ps
module Game_Controller_tb;
    logic clk=0,rst=1,enable=0;
    logic start_press=0,left_press=0,right_press=0,reset_press=0;
    logic [7:0] pipe_direction=0;
    logic [6:0] volume_bar=0;
    wire [2:0] state,selected;
    wire [1:0] level;
    wire [5:0] seconds_left,time_limit;
    wire [7:0] pipe_locked,initial_locked;
    wire [79:0] pipe_positions,target_positions,initial_positions;
    wire [9:0] source_y,goal_y,ball_x;
    wire [15:0] mid_codes,end_codes;
    wire [79:0] pipe_x_list;
    wire [6:0] pipe_half;
    wire [4:0] tube_half;
    wire [3:0] ball_radius;
    integer active,expected_y,initial_y,target_y,n;
    always #5 clk=~clk;
    Game_Level_Config config0(
        .level(level),.time_limit(time_limit),.source_y(source_y),.goal_y(goal_y),
        .target_positions(target_positions),.initial_positions(initial_positions),
        .initial_locked(initial_locked),.mid_codes(mid_codes),.end_codes(end_codes),
        .pipe_x_list(pipe_x_list),.pipe_half(pipe_half),.tube_half(tube_half),
        .ball_radius(ball_radius)
    );
    Game_Controller #(.TICK_CYCLES(3),.TICKS_PER_SECOND(100)) dut(
        .clk(clk),.rst(rst),.enable(enable),.start_press(start_press),
        .left_press(left_press),.right_press(right_press),.reset_press(reset_press),
        .pipe_direction(pipe_direction),.volume_bar(volume_bar),
        .target_positions(target_positions),.initial_positions(initial_positions),
        .initial_locked(initial_locked),.time_limit(time_limit),
        .mid_codes(mid_codes),.end_codes(end_codes),
        .pipe_half(pipe_half),.tube_half(tube_half),.state(state),
        .level(level),.selected(selected),.seconds_left(seconds_left),
        .pipe_locked(pipe_locked),.pipe_positions(pipe_positions),.ball_x(ball_x)
    );
    task automatic pulse_start;
        @(negedge clk);start_press=1;
        @(negedge clk);start_press=0;
    endtask
    task automatic pulse_right;
        @(negedge clk);right_press=1;
        @(negedge clk);right_press=0;
    endtask
    function automatic integer offset(input logic [1:0] code);
        case(code)
            2'd1:offset=pipe_half;
            2'd2:offset=-pipe_half;
            default:offset=0;
        endcase
    endfunction
    // Entrance limits that keep the whole pipe between y=128 and y=412.
    function automatic integer lo_bound(input integer k);
        lo_bound=128+tube_half+2+((mid_codes[k*2 +: 2]==2 || end_codes[k*2 +: 2]==2) ?
                                  pipe_half : 0);
    endfunction
    function automatic integer hi_bound(input integer k);
        hi_bound=412-tube_half-2-((mid_codes[k*2 +: 2]==1 || end_codes[k*2 +: 2]==1) ?
                                  pipe_half : 0);
    endfunction
    task automatic check_path(input integer count);
        integer last_x;
        begin
            expected_y=source_y;
            last_x=65;
            for(integer k=0;k<count;k=k+1) begin
                if(target_positions[k*10 +: 10] !== expected_y)
                    $fatal(1,"level %0d pipe %0d disconnected",level,k);
                if(mid_codes[k*2 +: 2]==3 || end_codes[k*2 +: 2]==3 ||
                   (mid_codes[k*2 +: 2]==1 && end_codes[k*2 +: 2]==2) ||
                   (mid_codes[k*2 +: 2]==2 && end_codes[k*2 +: 2]==1))
                    $fatal(1,"level %0d pipe %0d has an impossible shape",level,k);
                initial_y=initial_positions[k*10 +: 10];
                if(expected_y<lo_bound(k) || expected_y>hi_bound(k) ||
                   initial_y<lo_bound(k) || initial_y>hi_bound(k))
                    $fatal(1,"level %0d pipe %0d leaves the play area",level,k);
                if(initial_y-expected_y<=5 && expected_y-initial_y<=5)
                    $fatal(1,"level %0d pipe %0d starts aligned",level,k);
                if(pipe_x_list[k*10 +: 10]<=last_x)
                    $fatal(1,"level %0d pipe %0d overlaps on the left",level,k);
                last_x=pipe_x_list[k*10 +: 10]+2*pipe_half;
                expected_y=expected_y+offset(end_codes[k*2 +: 2]);
            end
            if(last_x>=552)
                $fatal(1,"level %0d pipes reach the goal",level);
            if(pipe_x_list[9:0]-65 > 20 || 552-last_x > 20)
                $fatal(1,"level %0d pipes are not spread across the screen",level);
            if(expected_y !== goal_y || source_y == goal_y)
                $fatal(1,"level %0d goal disconnected",level);
        end
    endtask
    task automatic play_stage(input integer stage,input integer count,input integer limit);
        begin
            if(level !== stage || state !== 3'd2 || seconds_left !== limit)
                $fatal(1,"stage %0d preview wrong: state=%0d time=%0d",stage,state,seconds_left);
            check_path(count);
            repeat(20) @(negedge clk);
            if(seconds_left !== limit) $fatal(1,"preview decremented timer");
            pulse_start();
            if(state !== 3'd3) $fatal(1,"second BTNU did not start play");
            volume_bar=7'h7f;
            // Driving the first pipe away from its target stops at the limit.
            initial_y=initial_positions[9:0];
            target_y=target_positions[9:0];
            pipe_direction[0]=(initial_y<target_y);
            repeat(180) @(negedge clk);
            if(pipe_locked[0] || pipe_positions[9:0] !==
               (initial_y<target_y ? lo_bound(0) : hi_bound(0)))
                $fatal(1,"stage %0d pipe 0 limit wrong: y=%0d",stage,pipe_positions[9:0]);
            for(integer k=0;k<count;k=k+1) begin
                if(selected !== k) $fatal(1,"selected pipe mismatch");
                initial_y=initial_positions[k*10 +: 10];
                target_y=target_positions[k*10 +: 10];
                pipe_direction[k]=(initial_y>target_y);
                n=0;
                while(!pipe_locked[k] && n<300) begin
                    @(negedge clk);n=n+1;
                end
                if(!pipe_locked[k] || pipe_positions[k*10 +: 10] !== target_y)
                    $fatal(1,"stage %0d pipe %0d did not lock",stage,k);
                if(k<count-1) pulse_right();
            end
            n=0;
            // ROLL starts one cycle after the last pipe locks.
            while((state==3'd3 || state==3'd4) && n<600) begin @(negedge clk);n=n+1;end
            if(state !== (stage==3 ? 3'd7 : 3'd5))
                $fatal(1,"stage %0d did not finish: state=%0d",stage,state);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst=0;
        repeat(3) @(negedge clk);
        if(state !== 3'd0) $fatal(1,"SW15-off title state missing");
        enable=1;repeat(3) @(negedge clk);
        if(state !== 3'd1) $fatal(1,"instruction screen missing");
        pulse_start();
        if(state !== 3'd2) $fatal(1,"first BTNU did not open preview");
        play_stage(1,4,40);
        pulse_start();repeat(2) @(negedge clk);
        play_stage(2,6,50);
        pulse_start();repeat(2) @(negedge clk);
        play_stage(3,8,60);
        pulse_start();repeat(2) @(negedge clk);
        if(state !== 3'd1 || level !== 1) $fatal(1,"win restart failed");
        volume_bar=0;
        pulse_start();pulse_start();
        repeat(12150) @(negedge clk);
        if(state !== 3'd6 || seconds_left !== 0)
            $fatal(1,"timeout failed: state=%0d time=%0d",state,seconds_left);
        @(negedge clk);reset_press=1;
        @(negedge clk);reset_press=0;
        if(state !== 3'd1 || level !== 1)
            $fatal(1,"BTND did not return to first-level instructions");
        enable=0;repeat(2) @(negedge clk);
        if(state !== 3'd0 || seconds_left !== 40)
            $fatal(1,"SW15 down did not restore title");
        $display("Game_Controller_tb PASS");$finish;
    end
endmodule
