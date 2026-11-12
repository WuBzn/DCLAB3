// 640x480 VGA at a 25 MHz pixel enable from the 100 MHz board clock.
module Game_VGA(
    input logic clk, rst, enable,
    input logic [2:0] state,
    input logic [1:0] level,
    input logic [2:0] selected,
    input logic [5:0] seconds_left,
    input logic [7:0] pipe_locked,
    input logic [79:0] pipe_positions, target_positions,
    input logic [15:0] mid_codes, end_codes,
    input logic [9:0] source_y, goal_y,
    input logic [7:0] pipe_direction,
    input logic [9:0] ball_x,
    input logic [6:0] volume_bar,
    output logic [3:0] VGA_R, VGA_G, VGA_B,
    output logic VGA_HS, VGA_VS
);
    localparam logic [2:0] OFF=0, INSTRUCTIONS=1, PREVIEW=2,
                           PLAY=3, ROLL=4, CLEAR=5, LOST=6, WON=7;
    logic [1:0] pixel_phase;
    logic [9:0] h,v;
    logic [2:0] state_frame;
    logic [1:0] level_frame;
    logic [2:0] selected_frame;
    logic [5:0] seconds_frame;
    logic [7:0] locked_frame,direction_frame;
    logic [79:0] positions_frame,targets_frame;
    logic [15:0] mid_frame,end_frame;
    logic [9:0] source_frame,goal_frame,ball_frame;
    logic [6:0] volume_frame;
    logic [3:0] active_count,volume_count,timer_tens,timer_ones;
    logic signed [11:0] ball_y,ball_dx,ball_dy,center_y,target_center;
    logic [9:0] pipe_x,pipe_y,target_y,ball_x0;
    logic [11:0] rgb, font_color;
    logic font_on;
    logic [7:0] font_char;
    logic [8*32-1:0] text_line;
    integer text_len,text_x,text_y,text_scale;
    integer text_col,text_row,char_index,local_col;
    integer i;
    logic [3:0] switch_number;

    function automatic logic signed [11:0] code_offset(input logic [1:0] code);
        case(code)
            2'd1: code_offset=12'sd26;
            2'd2: code_offset=-12'sd26;
            default: code_offset=0;
        endcase
    endfunction

    function automatic logic signed [11:0] pipe_center(
        input logic [9:0] entrance,
        input logic [6:0] local_pos,
        input logic [1:0] mid_code,end_code
    );
        logic signed [11:0] base,middle,exit_offset,run;
        begin
            base=$signed({2'b00,entrance});
            middle=code_offset(mid_code);
            exit_offset=code_offset(end_code);
            if(local_pos<7'd26) begin
                run=$signed({5'b0,local_pos});
                if(middle>0) pipe_center=base+run;
                else if(middle<0) pipe_center=base-run;
                else pipe_center=base;
            end else begin
                run=$signed({5'b0,local_pos-7'd26});
                if(exit_offset>middle) pipe_center=base+middle+run;
                else if(exit_offset<middle) pipe_center=base+middle-run;
                else pipe_center=base+middle;
            end
        end
    endfunction

    // Five-by-seven bitmap font, used for switch labels, direction and timer.
    function automatic logic [34:0] glyph(input logic [7:0] ch);
        case (ch)
            "0": glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
            "1": glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
            "2": glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
            "3": glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
            "4": glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
            "5": glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
            "6": glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
            "7": glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
            "8": glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
            "9": glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
            "A": glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
            "B": glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
            "C": glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
            "D": glyph={5'b11100,5'b10010,5'b10001,5'b10001,5'b10001,5'b10010,5'b11100};
            "E": glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
            "F": glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
            "G": glyph={5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01111};
            "H": glyph={5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
            "I": glyph={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
            "L": glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
            "M": glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
            "N": glyph={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
            "O": glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
            "P": glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
            "R": glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
            "S": glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
            "T": glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
            "U": glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
            "V": glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
            "W": glyph={5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b10101,5'b01010};
            "Y": glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
            default: glyph=35'b0;
        endcase
    endfunction

    function automatic logic font_pixel(
        input logic [7:0] ch, input logic [2:0] col, input logic [2:0] row
    );
        logic [34:0] bits;
        begin
            bits = glyph(ch);
            font_pixel = (col < 5 && row < 7) ? bits[34 - (row*5 + col)] : 1'b0;
        end
    endfunction

    // Snapshot all game inputs once per frame to avoid tearing.
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            pixel_phase<=0; h<=0; v<=0;
            state_frame<=OFF; level_frame<=1; selected_frame<=0;
            seconds_frame<=40; locked_frame<=8'hf0; direction_frame<=0;
            positions_frame<=0; targets_frame<=0; mid_frame<=0; end_frame<=0;
            source_frame<=264; goal_frame<=212; ball_frame<=48; volume_frame<=0;
        end else begin
            pixel_phase<=pixel_phase+1'b1;
            if(pixel_phase==2'd3) begin
                if(h==10'd799) begin
                    h<=0;
                    if(v==10'd524) v<=0;
                    else v<=v+1'b1;
                end else h<=h+1'b1;
                if(h==0 && v==0) begin
                    state_frame<=enable ? state : OFF;
                    level_frame<=level; selected_frame<=selected;
                    seconds_frame<=seconds_left; locked_frame<=pipe_locked;
                    direction_frame<=pipe_direction; positions_frame<=pipe_positions;
                    targets_frame<=target_positions; mid_frame<=mid_codes;
                    end_frame<=end_codes; source_frame<=source_y;
                    goal_frame<=goal_y; ball_frame<=ball_x; volume_frame<=volume_bar;
                end
            end
        end
    end
    assign VGA_HS=!(h>=10'd656 && h<10'd752);
    assign VGA_VS=!(v>=10'd490 && v<10'd492);

    always_comb begin
        active_count=level_frame==1 ? 4'd4 : level_frame==2 ? 4'd6 : 4'd8;
        ball_y=$signed({2'b00,source_frame});
        ball_x0=0;
        for(integer k=0;k<8;k=k+1) begin
            ball_x0=10'(72+k*60);
            if(k<active_count) begin
                if(ball_frame>=ball_x0+10'd52)
                    ball_y=$signed({2'b00,targets_frame[k*10 +: 10]})+
                           code_offset(end_frame[k*2 +: 2]);
                else if(ball_frame>=ball_x0)
                    ball_y=pipe_center(targets_frame[k*10 +: 10],
                                       7'(ball_frame-ball_x0),
                                       mid_frame[k*2 +: 2],end_frame[k*2 +: 2]);
            end
        end
        ball_dx=$signed({2'b00,h})-$signed({2'b00,ball_frame});
        ball_dy=$signed({2'b00,v})-ball_y;
        volume_count=0;
        for(integer k=0;k<7;k=k+1) volume_count=volume_count+volume_frame[k];
        if(seconds_frame>=60) begin timer_tens=6;timer_ones=seconds_frame-60;end
        else if(seconds_frame>=50) begin timer_tens=5;timer_ones=seconds_frame-50;end
        else if(seconds_frame>=40) begin timer_tens=4;timer_ones=seconds_frame-40;end
        else if(seconds_frame>=30) begin timer_tens=3;timer_ones=seconds_frame-30;end
        else if(seconds_frame>=20) begin timer_tens=2;timer_ones=seconds_frame-20;end
        else if(seconds_frame>=10) begin timer_tens=1;timer_ones=seconds_frame-10;end
        else begin timer_tens=0;timer_ones=seconds_frame[3:0];end
    end

    // Exactly one active text line is rasterized at a pixel.
    always_comb begin
        text_line='0; text_len=0; text_x=0; text_y=0; text_scale=1;
        font_color=12'hdef; font_char=" "; font_on=0;
        text_col=0; text_row=0; char_index=0; local_col=0;
        switch_number=0;
        if(state_frame==OFF) begin
            if(v>=142 && v<170) begin
                text_line="DCLAB"; text_len=5; text_x=260; text_y=142; text_scale=4;
                font_color=12'h7ef;
            end else if(v>=209 && v<230) begin
                text_line="GROUP11"; text_len=7; text_x=257; text_y=209; text_scale=3;
                font_color=12'hfd7;
            end else if(v>=336 && v<350) begin
                text_line="SW15 TO ENTER"; text_len=13; text_x=242; text_y=336; text_scale=2;
                font_color=12'hdef;
            end
        end else if(state_frame==INSTRUCTIONS) begin
            if(v>=73 && v<94) begin
                text_line="HOW TO PLAY"; text_len=11; text_x=221; text_y=73; text_scale=3;
                font_color=12'h7ef;
            end else if(v>=126 && v<140) begin
                text_line="BTNL BTNR SELECT PIPE"; text_len=21; text_x=165; text_y=126; text_scale=2;
            end else if(v>=162 && v<176) begin
                text_line="SW14 TO SW07 SET UP DN"; text_len=22; text_x=158; text_y=162; text_scale=2;
            end else if(v>=198 && v<212) begin
                text_line="VOICE MOVES SELECTED PIPE"; text_len=25; text_x=145; text_y=198; text_scale=2;
            end else if(v>=234 && v<248) begin
                text_line="ALIGN PIPES TO ROLL BALL"; text_len=24; text_x=151; text_y=234; text_scale=2;
            end else if(v>=270 && v<284) begin
                text_line="BTND RESET"; text_len=10; text_x=260; text_y=270; text_scale=2;
            end else if(v>=345 && v<359) begin
                text_line="BTNU PREVIEW"; text_len=12; text_x=248; text_y=345; text_scale=2;
                font_color=12'hfd7;
            end
        end else begin
            if(v>=10 && v<17) begin
                if(h<100) begin text_line="LEVEL";text_len=5;text_x=24;text_y=10;end
                else if(h>=300 && h<375) begin text_line="TIME";text_len=4;text_x=307;text_y=10;end
                else if(h>=500) begin text_line="PIPE";text_len=4;text_x=507;text_y=10;end
                font_color=12'h9bd;
            end else if(v>=23 && v<44 && h>=449 && h<485) begin
                text_line={8'("0"+timer_tens),8'("0"+timer_ones)};
                text_len=2;text_x=449;text_y=23;text_scale=3;
                font_color=seconds_frame<=10 ? 12'hf65 : 12'hfff;
            end else if(v>=444 && v<451) begin
                text_line="VOICE";text_len=5;text_x=21;text_y=444;
                font_color=12'h9bd;
            end else if(v>=371 && v<385 &&
                        (state_frame==PREVIEW || state_frame==CLEAR ||
                         state_frame==LOST || state_frame==WON)) begin
                if(state_frame==PREVIEW) begin text_line="BTNU START";text_len=10;end
                else if(state_frame==CLEAR) begin text_line="LEVEL CLEAR";text_len=11;end
                else if(state_frame==LOST) begin text_line="TIME UP";text_len=7;end
                else begin text_line="YOU WIN";text_len=7;end
                text_x=320-text_len*6;text_y=371;text_scale=2;
                font_color=state_frame==LOST ? 12'hf75 : 12'h7ff;
            end
            for(integer k=0;k<8;k=k+1) begin
                if(k<active_count && h>=86+k*60 && h<110+k*60 &&
                   v>=90 && v<97) begin
                    switch_number=4'(14-k);
                    text_line={"S","W",8'("0"+(switch_number>=10 ? 1 : 0)),
                               8'("0"+(switch_number>=10 ? switch_number-10 : switch_number))};
                    text_len=4;text_x=86+k*60;text_y=90;text_scale=1;
                    font_color=k==selected_frame ? 12'h2ff : 12'hdef;
                end else if(k<active_count && h>=92+k*60 && h<104+k*60 &&
                            v>=109 && v<116) begin
                    text_line=direction_frame[k] ? "UP" : "DN";
                    text_len=2;text_x=92+k*60;text_y=109;text_scale=1;
                    font_color=direction_frame[k] ? 12'h7df : 12'hfd8;
                end
            end
        end
        if(text_len>0 && h>=text_x && h<text_x+text_len*6*text_scale &&
           v>=text_y && v<text_y+7*text_scale) begin
            text_col=(h-text_x)/text_scale;
            text_row=(v-text_y)/text_scale;
            char_index=text_col/6;
            local_col=text_col%6;
            font_char=text_line[(text_len-1-char_index)*8 +: 8];
            font_on=local_col<5 && font_pixel(font_char,3'(local_col),3'(text_row));
        end
    end

    always_comb begin
        rgb=12'h000; pipe_x=0;pipe_y=0;target_y=0;
        center_y=0;target_center=0;
        if(h<640 && v<480) begin
            rgb=v<66 ? 12'h124 : v<422 ? 12'h112 : 12'h124;
            if(v>=66 && v<422 && (h[4:0]==0 || v[4:0]==0)) rgb=12'h223;
            if(v>=63 && v<67) rgb=12'h0bd;
            if(v>=419 && v<423) rgb=12'h0bd;
            if(state_frame==OFF) begin
                rgb=v<240 ? 12'h123 : 12'h112;
                if((h[5:0]==0 || v[5:0]==0) && v>55 && v<420) rgb=12'h234;
                if(h>=88 && h<552 && v>=94 && v<397) begin
                    if(h<92 || h>=548 || v<98 || v>=393) rgb=12'h0bd;
                end
                if(h>=140 && h<500 && v>=300 && v<374)
                    rgb=(h<144 || h>=496 || v<304 || v>=370) ? 12'hfc5 : 12'h234;
            end else if(state_frame==INSTRUCTIONS) begin
                if(h>=74 && h<566 && v>=56 && v<406)
                    rgb=(h<78 || h>=562 || v<60 || v>=402) ? 12'h0bd : 12'h123;
                if(h>=165 && h<475 && v>=326 && v<380)
                    rgb=(h<169 || h>=471 || v<330 || v>=376) ? 12'hfc5 : 12'h234;
            end else begin
                // Three level blocks at upper left, eight pipe-status blocks at upper right.
                for(i=0;i<3;i=i+1)
                    if(h>=24+i*23 && h<42+i*23 && v>=25 && v<43)
                        rgb=i<level_frame ? 12'hfd5 : 12'h456;
                if(h>=141 && h<440 && v>=20 && v<47) rgb=12'h456;
                if(h>=145 && h<440 &&
                   h<145+10'(seconds_frame)*10'd5 && v>=24 && v<43)
                    rgb=seconds_frame<=10 ? 12'hf54 : 12'hfd5;
                for(i=0;i<8;i=i+1)
                    if(h>=506+i*15 && h<518+i*15 && v>=27 && v<43)
                        rgb=i==selected_frame ? 12'h2ef :
                            i<active_count ? (locked_frame[i] ? 12'h5e7 : 12'hb67) :
                            12'h345;
                // Compact cards show exact switch and current direction.
                for(i=0;i<8;i=i+1) begin
                    pipe_x=10'(72+i*60);
                    if(i<active_count && h>=pipe_x+2 && h<pipe_x+50 &&
                       v>=82 && v<122)
                        rgb=(h<pipe_x+4 || h>=pipe_x+48 || v<84 || v>=120) ?
                            (i==selected_frame ? 12'h2ef :
                             locked_frame[i] ? 12'h3a6 : 12'h567) : 12'h234;
                end
                // Source, goal, and faint target route.
                if(h<65 && v>=source_frame-11 && v<=source_frame+11) rgb=12'h4df;
                if(h>=552 && h<599 && v>=goal_frame-11 && v<=goal_frame+11)
                    rgb=12'h6e6;
                if(h>=592 && h<625 && v>=goal_frame-28 && v<=goal_frame+28)
                    rgb=12'h0a4;
                if(h>=600 && h<625 && v>=goal_frame-20 && v<=goal_frame+20)
                    rgb=12'h012;
                for(i=0;i<8;i=i+1) begin
                    pipe_x=10'(72+i*60);
                    pipe_y=positions_frame[i*10 +: 10];
                    target_y=targets_frame[i*10 +: 10];
                    if(i<active_count && h>=pipe_x && h<pipe_x+52) begin
                        center_y=pipe_center(pipe_y,7'(h-pipe_x),
                                              mid_frame[i*2 +: 2],end_frame[i*2 +: 2]);
                        target_center=pipe_center(target_y,7'(h-pipe_x),
                                                  mid_frame[i*2 +: 2],end_frame[i*2 +: 2]);
                        if(h[2:1]!=0 && v>=target_center-1 && v<=target_center+1)
                            rgb=12'h567;
                        if(v>=center_y-13 && v<=center_y+13)
                            rgb=i==selected_frame ? 12'h2df : 12'h789;
                        if(v>=center_y-9 && v<=center_y+9)
                            rgb=locked_frame[i] ? 12'h174 : 12'h643;
                        if(v>=center_y-6 && v<=center_y+6)
                            rgb=locked_frame[i] ? 12'h5e8 :
                                i==selected_frame ? 12'h4df : 12'he94;
                        if(v>=center_y-12 && v<=center_y-11) rgb=12'habc;
                        if((h<pipe_x+3 || h>=pipe_x+49) &&
                           v>=center_y-15 && v<=center_y+15)
                            rgb=locked_frame[i] ? 12'h4b6 :
                                i==selected_frame ? 12'h2ff : 12'hb86;
                    end
                end
                if(ball_dx>=-8 && ball_dx<=8 && ball_dy>=-8 && ball_dy<=8 &&
                   (ball_dx<0 ? -ball_dx : ball_dx)+
                   (ball_dy<0 ? -ball_dy : ball_dy)<=12)
                    rgb=ball_dx<-2 || ball_dy>3 ? 12'hc82 : 12'hff4;
                if(ball_dx>=-4 && ball_dx<=-2 &&
                   ball_dy>=-4 && ball_dy<=-2) rgb=12'hfff;
                if(v>=439 && v<464 && h>=90 && h<552) rgb=12'h789;
                if(v>=442 && v<461 && h>=94 && h<548) rgb=12'h123;
                if(v>=442 && v<461 && h>=94 && h<94+10'(volume_count)*10'd64)
                    rgb=volume_count>=5 ? 12'hf73 : 12'h3dc;
                if((state_frame==PREVIEW || state_frame==CLEAR ||
                    state_frame==LOST || state_frame==WON) &&
                    h>=226 && h<414 && v>=350 && v<404)
                    rgb=(h<230 || h>=410 || v<354 || v>=400) ?
                        (state_frame==LOST ? 12'hf45 : 12'h2dc) : 12'h234;
            end
            if(font_on) rgb=font_color;
        end
    end
    assign {VGA_R,VGA_G,VGA_B}=(h<640 && v<480) ? rgb : 12'h000;
endmodule
