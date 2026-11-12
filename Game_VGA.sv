// 640x480 VGA at a 25 MHz pixel enable from the 100 MHz board clock.
// The colour is computed combinationally from the pixel counters and a
// per-frame snapshot, then registered once per pixel together with HS/VS.
// Every register feeding the colour logic changes only on the pixel enable,
// so that logic has four clock cycles (see game_timing.xdc).
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
    input logic [79:0] pipe_x_list,
    input logic [6:0] pipe_half,
    input logic [4:0] tube_half,
    input logic [3:0] ball_radius,
    input logic [1:0] sensitivity,
    output logic [3:0] VGA_R, VGA_G, VGA_B,
    output logic VGA_HS, VGA_VS
);
    localparam logic [2:0] OFF=0, INSTRUCTIONS=1, PREVIEW=2,
                           PLAY=3, ROLL=4, CLEAR=5, LOST=6, WON=7;
    // Left edges of the four instruction cards.
    localparam int C1=86, C2=206, C3=326, C4=446;

    logic [1:0] pixel_phase;
    logic [9:0] h,v;
    logic [6:0] anim;                 // frame counter for the demo animations
    logic [2:0] state_frame;
    logic [1:0] level_frame;
    logic [2:0] selected_frame;
    logic [5:0] seconds_frame;
    logic [7:0] locked_frame,direction_frame;
    logic [79:0] positions_frame,targets_frame,xlist_frame;
    logic [15:0] mid_frame,end_frame;
    logic [9:0] source_frame,goal_frame,ball_frame;
    logic [6:0] volume_frame,half_frame;
    logic [4:0] tube_frame;
    logic [3:0] ballr_frame;
    logic [1:0] sens_frame;

    logic [3:0] active_count,volume_count,timer_tens,timer_ones;
    logic [7:0] pipe_w;
    logic [9:0] status_x0;
    logic signed [11:0] ball_y;
    logic [1:0] demo_sel;
    logic demo_left,demo_up;
    logic [5:0] demo_prog;
    logic [6:0] demo_ball;
    logic [31:0] sens_text;
    logic [2:0] sens_len;

    logic [11:0] rgb,rgb_q,font_color;
    logic hs_q,vs_q;
    logic font_on;
    logic [7:0] font_char;
    logic [8*16-1:0] text_line;
    logic [31:0] sw_text;
    logic [15:0] timer_text;
    logic [4:0] text_len;
    logic [9:0] text_x,text_y,text_dx,text_dy,text_col,text_row;
    logic [2:0] text_scale;
    logic [7:0] char_index;
    logic [2:0] local_col;

    // ---------------------------------------------------------------
    // Pipe geometry
    // ---------------------------------------------------------------
    function automatic logic signed [11:0] code_offset(
        input logic [1:0] code, input logic [6:0] half
    );
        case(code)
            2'd1: code_offset=$signed({5'b0,half});
            2'd2: code_offset=-$signed({5'b0,half});
            default: code_offset=12'sd0;
        endcase
    endfunction

    function automatic logic signed [11:0] pipe_center(
        input logic [9:0] entrance,
        input logic [6:0] local_pos,
        input logic [1:0] mid_code,end_code,
        input logic [6:0] half
    );
        logic signed [11:0] base,middle,exit_offset,run;
        begin
            base=$signed({2'b00,entrance});
            middle=code_offset(mid_code,half);
            exit_offset=code_offset(end_code,half);
            if(local_pos<half) begin
                run=$signed({5'b0,local_pos});
                if(middle>0) pipe_center=base+run;
                else if(middle<0) pipe_center=base-run;
                else pipe_center=base;
            end else begin
                run=$signed({5'b0,7'(local_pos-half)});
                if(exit_offset>middle) pipe_center=base+middle+run;
                else if(exit_offset<middle) pipe_center=base+middle-run;
                else pipe_center=base+middle;
            end
        end
    endfunction

    // ---------------------------------------------------------------
    // Five-by-seven bitmap font
    // ---------------------------------------------------------------
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
            "X": glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
            "Y": glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
            ".": glyph={5'b00000,5'b00000,5'b00000,5'b00000,5'b00000,5'b01100,5'b01100};
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

    // ---------------------------------------------------------------
    // Icon primitives (all coordinates in screen pixels)
    // ---------------------------------------------------------------
    function automatic int iabs(input int a);
        iabs = a < 0 ? -a : a;
    endfunction

    function automatic logic in_box(input int px,py,x,y,w,hh);
        in_box = px>=x && px<x+w && py>=y && py<y+hh;
    endfunction

    // 30x16 push button: 0 outside, 1 rim, 2 face.
    function automatic logic [1:0] button_px(input int px,py,x,y);
        int dx,dy;
        begin
            dx=px-x; dy=py-y;
            if(dx<0 || dx>=30 || dy<0 || dy>=16) button_px=2'd0;
            else if((dx==0 || dx==29) && (dy==0 || dy==15)) button_px=2'd0;
            else if(dx<2 || dx>=28 || dy<2 || dy>=14) button_px=2'd1;
            else button_px=2'd2;
        end
    endfunction

    // Slide switch, knob at the top when up: 0 outside, 1 frame, 2 slot, 3 knob.
    function automatic logic [1:0] switch_px(input int px,py,x,y,w,hh,
                                             input logic up);
        int dx,dy,kh;
        begin
            dx=px-x; dy=py-y; kh=(hh-4)>>1;
            if(dx<0 || dx>=w || dy<0 || dy>=hh) switch_px=2'd0;
            else if(dx<1 || dx>=w-1 || dy<1 || dy>=hh-1) switch_px=2'd1;
            else if(dx>=2 && dx<w-2 &&
                    (up ? (dy>=2 && dy<2+kh) : (dy>=hh-2-kh && dy<hh-2)))
                switch_px=2'd3;
            else switch_px=2'd2;
        end
    endfunction

    // Vertical arrow centred on cx, 2*hw+1 wide and hh tall; shaft 2*sw+1 wide.
    function automatic logic arrow_px(input int px,py,cx,y,hw,hh,sw,
                                      input logic up);
        int dx,dy;
        begin
            dx=iabs(px-cx);
            dy=up ? py-y : y+hh-1-py;
            if(dy<0 || dy>=hh) arrow_px=1'b0;
            else if(dy<=hw) arrow_px=dx<=dy;
            else arrow_px=dx<=sw;
        end
    endfunction

    // Horizontal triangle len pixels long, tip on the right (or left).
    function automatic logic tri_px(input int px,py,x,cy,len,input logic right);
        int dx,dy;
        begin
            dy=iabs(py-cy);
            dx=right ? px-x : x+len-px;
            tri_px=px>=x && px<=x+len && dx>=0 && dx+dy<=len;
        end
    endfunction

    // Ball: 0 outside, 1 shade, 2 body, 3 highlight.
    function automatic logic [1:0] ball_px(input int px,py,cx,cy,r);
        int dx,dy;
        begin
            dx=px-cx; dy=py-cy;
            ball_px=2'd0;
            if(iabs(dx)<=r && iabs(dy)<=r && iabs(dx)+iabs(dy)<=r+(r>>1))
                ball_px=(dx < -(r>>2) || dy > (r>>1)-1) ? 2'd1 : 2'd2;
            if(dx>=-(r>>1) && dx<=-(r>>2) && dy>=-(r>>1) && dy<=-(r>>2))
                ball_px=2'd3;
        end
    endfunction

    // Path of the small "aligned pipe" demo in instruction card 4.
    function automatic int demo_path(input int lx);
        if(lx<30) demo_path=200;
        else if(lx<54) demo_path=200-(lx-30);
        else if(lx<66) demo_path=176;
        else if(lx<90) demo_path=176+(lx-66);
        else demo_path=200;
    endfunction

    // ---------------------------------------------------------------
    // Counters, frame snapshot and the registered output
    // ---------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            pixel_phase<=0; h<=0; v<=0; anim<=0;
            state_frame<=OFF; level_frame<=1; selected_frame<=0;
            seconds_frame<=40; locked_frame<=8'hf0; direction_frame<=0;
            positions_frame<=0; targets_frame<=0; mid_frame<=0; end_frame<=0;
            source_frame<=330; goal_frame<=226; ball_frame<=48; volume_frame<=0;
            xlist_frame<=0; half_frame<=52; tube_frame<=20; ballr_frame<=11;
            sens_frame<=0;
        end else begin
            pixel_phase<=pixel_phase+1'b1;
            if(pixel_phase==2'd3) begin
                if(h==10'd799) begin
                    h<=0;
                    if(v==10'd524) v<=0;
                    else v<=v+1'b1;
                end else h<=h+1'b1;
                if(h==0 && v==0) begin
                    anim<=anim+1'b1;
                    state_frame<=enable ? state : OFF;
                    level_frame<=level; selected_frame<=selected;
                    seconds_frame<=seconds_left; locked_frame<=pipe_locked;
                    direction_frame<=pipe_direction; positions_frame<=pipe_positions;
                    targets_frame<=target_positions; mid_frame<=mid_codes;
                    end_frame<=end_codes; source_frame<=source_y;
                    goal_frame<=goal_y; ball_frame<=ball_x; volume_frame<=volume_bar;
                    xlist_frame<=pipe_x_list; half_frame<=pipe_half;
                    tube_frame<=tube_half; ballr_frame<=ball_radius;
                    sens_frame<=sensitivity;
                end
            end
        end
    end

    // One pixel of delay for colour and sync alike.
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            rgb_q<=12'h000; hs_q<=1'b1; vs_q<=1'b1;
        end else if(pixel_phase==2'd3) begin
            rgb_q<=(h<640 && v<480) ? rgb : 12'h000;
            hs_q<=!(h>=10'd656 && h<10'd752);
            vs_q<=!(v>=10'd490 && v<10'd492);
        end
    end
    assign {VGA_R,VGA_G,VGA_B}=rgb_q;
    assign VGA_HS=hs_q;
    assign VGA_VS=vs_q;

    // ---------------------------------------------------------------
    // Per-frame derived values
    // ---------------------------------------------------------------
    always_comb begin
        active_count=level_frame==2'd1 ? 4'd4 : level_frame==2'd2 ? 4'd6 : 4'd8;
        pipe_w={half_frame,1'b0};
        status_x0=10'd506+((10'(4'd8-active_count)*10'd15)>>1);
        ball_y=$signed({2'b00,source_frame});
        for(int k=0;k<8;k=k+1) begin
            if(k<active_count) begin
                if(ball_frame>=xlist_frame[k*10 +: 10]+10'(pipe_w))
                    ball_y=$signed({2'b00,targets_frame[k*10 +: 10]})+
                           code_offset(end_frame[k*2 +: 2],half_frame);
                else if(ball_frame>=xlist_frame[k*10 +: 10])
                    ball_y=pipe_center(targets_frame[k*10 +: 10],
                                       7'(ball_frame-xlist_frame[k*10 +: 10]),
                                       mid_frame[k*2 +: 2],end_frame[k*2 +: 2],
                                       half_frame);
            end
        end
        volume_count=0;
        for(int k=0;k<7;k=k+1) volume_count=volume_count+volume_frame[k];
        if(seconds_frame>=60) begin timer_tens=6;timer_ones=seconds_frame-60;end
        else if(seconds_frame>=50) begin timer_tens=5;timer_ones=seconds_frame-50;end
        else if(seconds_frame>=40) begin timer_tens=4;timer_ones=seconds_frame-40;end
        else if(seconds_frame>=30) begin timer_tens=3;timer_ones=seconds_frame-30;end
        else if(seconds_frame>=20) begin timer_tens=2;timer_ones=seconds_frame-20;end
        else if(seconds_frame>=10) begin timer_tens=1;timer_ones=seconds_frame-10;end
        else begin timer_tens=0;timer_ones=seconds_frame[3:0];end
        // Demo animation: selection walks 0,1,2,1; switch flips every ~1 s.
        demo_sel=anim[6:5]==2'd3 ? 2'd1 : anim[6:5];
        demo_left=anim[6];
        demo_up=!anim[6];
        demo_prog=6'((anim[5:0]*3)>>2);
        demo_ball=7'((anim*5)>>3);
        case(sens_frame)
            2'd0: begin sens_text="1.5X"; sens_len=4; end
            2'd1: begin sens_text="2X";   sens_len=2; end
            2'd2: begin sens_text="2.5X"; sens_len=4; end
            default: begin sens_text="3X"; sens_len=2; end
        endcase
    end

    // ---------------------------------------------------------------
    // Text: exactly one text box is rasterized at a pixel
    // ---------------------------------------------------------------
`define GV_TEXT(STR,LEN,X,Y,S,COL) \
    if(in_box(h,v,(X),(Y),(LEN)*6*(S),7*(S))) begin \
        text_line=STR; text_len=5'(LEN); text_x=10'(X); text_y=10'(Y); \
        text_scale=3'(S); font_color=COL; \
    end

    always_comb begin
        text_line='0; text_len=0; text_x=0; text_y=0; text_scale=1;
        sw_text=0; timer_text=0;
        font_color=12'hdef; font_char=" "; font_on=0;
        text_dx=0; text_dy=0; text_col=0; text_row=0; char_index=0; local_col=0;
        if(state_frame==OFF) begin
            `GV_TEXT("DCLAB",5,260,142,4,12'h7ef)
            `GV_TEXT("GROUP11",7,257,209,3,12'hfd7)
            `GV_TEXT("SW15 UP TO PLAY",15,246,330,2,12'hdef)
        end else if(state_frame==INSTRUCTIONS) begin
            `GV_TEXT("HOW TO PLAY",11,221,68,3,12'h7ef)
            // Step numbers on the card badges.
            `GV_TEXT("1",1,C1+9,107,2,12'h123)
            `GV_TEXT("2",1,C2+9,107,2,12'h123)
            `GV_TEXT("3",1,C3+9,107,2,12'h123)
            `GV_TEXT("4",1,C4+9,107,2,12'h123)
            // Card 1: buttons.
            `GV_TEXT("BTNU",4,C1+42,139,1,12'h89a)
            `GV_TEXT("BTNL",4,C1+8,161,1,12'h012)
            `GV_TEXT("BTNC",4,C1+42,161,1,12'h89a)
            `GV_TEXT("BTNR",4,C1+76,161,1,12'h012)
            `GV_TEXT("BTND",4,C1+42,183,1,12'h89a)
            // Card 2: switch.
            `GV_TEXT("UP",2,C2+50,140,2,demo_up ? 12'h7df : 12'h456)
            `GV_TEXT("DN",2,C2+50,178,2,demo_up ? 12'h456 : 12'hfd8)
            // Card titles and captions.
            `GV_TEXT("SELECT",6,C1+18,248,2,12'h7ef)
            `GV_TEXT("SWITCH",6,C2+18,248,2,12'h7ef)
            `GV_TEXT("VOICE",5,C3+24,248,2,12'h7ef)
            `GV_TEXT("ALIGN",5,C4+24,248,2,12'h7ef)
            `GV_TEXT("CHOOSE PIPE",11,C1+21,268,1,12'h9bd)
            `GV_TEXT("SW14 TO SW07",12,C2+18,268,1,12'h9bd)
            `GV_TEXT("LOUDER FASTER",13,C3+15,268,1,12'h9bd)
            `GV_TEXT("BALL TO HOLE",12,C4+18,268,1,12'h9bd)
            // Bottom rows.
            `GV_TEXT("BTNU",4,141,309,1,12'h210)
            `GV_TEXT("PREVIEW",7,178,305,2,12'hfd7)
            `GV_TEXT("BTND",4,393,309,1,12'hdde)
            `GV_TEXT("RESET",5,430,305,2,12'hdde)
            `GV_TEXT("MIC",3,96,362,2,12'h9bd)
            `GV_TEXT("SW1",3,400,348,1,12'h9bd)
            `GV_TEXT("SW0",3,424,348,1,12'h9bd)
            `GV_TEXT("SENS",4,456,348,1,12'h9bd)
            `GV_TEXT(sens_text,sens_len,456,362,2,12'hfd7)
        end else begin
            `GV_TEXT("LEVEL",5,24,10,1,12'h9bd)
            `GV_TEXT("TIME",4,307,10,1,12'h9bd)
            `GV_TEXT("PIPE",4,507,10,1,12'h9bd)
            timer_text={8'("0"+timer_tens),8'("0"+timer_ones)};
            `GV_TEXT(timer_text,2,449,23,3,seconds_frame<=10 ? 12'hf65 : 12'hfff)
            `GV_TEXT("SENS",4,566,432,1,12'h9bd)
            `GV_TEXT(sens_text,sens_len,566,443,2,12'hfd7)
            if(state_frame==PREVIEW) begin
                // The start prompt sits in the bottom panel so that the
                // whole puzzle stays visible during the preview.
                `GV_TEXT("BTNU",4,273,448,1,12'h210)
                `GV_TEXT("START",5,310,444,2,12'h7ff)
            end else begin
                `GV_TEXT("VOICE",5,21,444,1,12'h9bd)
            end
            if(state_frame==CLEAR) begin
                `GV_TEXT("LEVEL CLEAR",11,254,356,2,12'h7ff)
                `GV_TEXT("BTNU",4,279,383,1,12'h210)
                `GV_TEXT("NEXT",4,316,379,2,12'hdfe)
            end else if(state_frame==LOST) begin
                `GV_TEXT("TIME UP",7,278,356,2,12'hf75)
                `GV_TEXT("BTNU",4,273,383,1,12'h210)
                `GV_TEXT("RETRY",5,310,379,2,12'hdfe)
            end else if(state_frame==WON) begin
                `GV_TEXT("YOU WIN",7,278,356,2,12'h7ff)
                `GV_TEXT("BTNU",4,279,383,1,12'h210)
                `GV_TEXT("MENU",4,316,379,2,12'hdfe)
            end
            // Switch number above each pipe card.
            for(int k=0;k<8;k=k+1) begin
                if(k<active_count) begin
                    sw_text={"S","W",8'("0"+(14-k>=10 ? 1 : 0)),
                             8'("0"+(14-k>=10 ? 4-k : 14-k))};
                    `GV_TEXT(sw_text,4,int'(xlist_frame[k*10 +: 10])+int'(half_frame)-12,
                             84,1,k==selected_frame ? 12'h2ff : 12'hdef)
                end
            end
        end
        if(text_len!=0) begin
            text_dx=h-text_x;
            text_dy=v-text_y;
            case(text_scale)
                3'd1: begin text_col=text_dx; text_row=text_dy; end
                3'd2: begin text_col=text_dx>>1; text_row=text_dy>>1; end
                3'd3: begin text_col=text_dx/3; text_row=text_dy/3; end
                default: begin text_col=text_dx>>2; text_row=text_dy>>2; end
            endcase
            char_index=8'(text_col/6);
            local_col=3'(text_col%6);
            font_char=text_line[(int'(text_len)-1-int'(char_index))*8 +: 8];
            font_on=local_col<5 && font_pixel(font_char,local_col,3'(text_row));
        end
    end
`undef GV_TEXT

    // ---------------------------------------------------------------
    // Pixel colour
    // ---------------------------------------------------------------
    always_comb begin
        int cx,cy,dyc,tdy,mdx,mdy,lx,d2,px0,bx;
        logic signed [11:0] center_y,target_center;
        logic [1:0] b;
        rgb=12'h000;
        cx=0; cy=0; dyc=0; tdy=0; mdx=0; mdy=0; lx=0; d2=0; px0=0; bx=0;
        center_y=0; target_center=0; b=0;
        if(h<640 && v<480) begin
            rgb=v<66 ? 12'h124 : v<422 ? 12'h112 : 12'h124;
            if(v>=66 && v<422 && (h[4:0]==0 || v[4:0]==0)) rgb=12'h223;
            if(v>=63 && v<67) rgb=12'h0bd;
            if(v>=419 && v<423) rgb=12'h0bd;
            if(state_frame==OFF) begin
                // ---------------- Title page ----------------
                rgb=v<240 ? 12'h123 : 12'h112;
                if((h[5:0]==0 || v[5:0]==0) && v>55 && v<420) rgb=12'h234;
                if(h>=88 && h<552 && v>=94 && v<397 &&
                   (h<92 || h>=548 || v<98 || v>=393)) rgb=12'h0bd;
                if(h>=140 && h<500 && v>=300 && v<374)
                    rgb=(h<144 || h>=496 || v<304 || v>=370) ? 12'hfc5 : 12'h234;
                case(switch_px(h,v,214,316,16,42,anim[5]))
                    2'd1: rgb=12'h9ab;
                    2'd2: rgb=12'h123;
                    2'd3: rgb=12'hfd7;
                    default: ;
                endcase
            end else if(state_frame==INSTRUCTIONS) begin
                // ---------------- Instructions ----------------
                if(h>=74 && h<566 && v>=56 && v<406)
                    rgb=(h<78 || h>=562 || v<60 || v>=402) ? 12'h0bd : 12'h123;
                for(int c=0;c<4;c=c+1) begin
                    cx=C1+c*120;
                    if(in_box(h,v,cx,100,108,184))
                        rgb=(h<cx+2 || h>=cx+106 || v<102 || v>=282) ?
                            12'h456 : 12'h234;
                    if(in_box(h,v,cx+6,106,16,16)) rgb=12'h0bd;
                    if(c<3 && tri_px(h,v,cx+110,192,6,1'b1)) rgb=12'h0bd;
                end

                // Card 1: the five push buttons as laid out on the board.
                b=button_px(h,v,C1+39,134); if(b!=0) rgb=b==1 ? 12'h567 : 12'h345;
                b=button_px(h,v,C1+39,156); if(b!=0) rgb=b==1 ? 12'h567 : 12'h345;
                b=button_px(h,v,C1+39,178); if(b!=0) rgb=b==1 ? 12'h567 : 12'h345;
                b=button_px(h,v,C1+5,156);
                if(b!=0) rgb=b==1 ? (demo_left ? 12'hfff : 12'h7ef) :
                                    (demo_left ? 12'h5ef : 12'h2bd);
                b=button_px(h,v,C1+73,156);
                if(b!=0) rgb=b==1 ? (demo_left ? 12'h7ef : 12'hfff) :
                                    (demo_left ? 12'h2bd : 12'h5ef);
                for(int j=0;j<3;j=j+1) begin
                    cx=C1+20+j*24;
                    if(in_box(h,v,cx,208,20,12))
                        rgb=(h<cx+2 || h>=cx+18 || v<210 || v>=218) ?
                            (j==demo_sel ? 12'h2ff : 12'hb86) :
                            (j==demo_sel ? 12'h4df : 12'he94);
                end
                if(tri_px(h,v,C1+6,214,7,1'b0)) rgb=demo_left ? 12'hfff : 12'h4ab;
                if(tri_px(h,v,C1+93,214,7,1'b1)) rgb=demo_left ? 12'h4ab : 12'hfff;

                // Card 2: a slide switch flips and the pipe follows it.
                case(switch_px(h,v,C2+16,134,26,64,demo_up))
                    2'd1: rgb=12'h9ab;
                    2'd2: rgb=12'h123;
                    2'd3: rgb=demo_up ? 12'h7df : 12'hfd8;
                    default: ;
                endcase
                if(h==C2+91 && v>=136 && v<198 && v[2]) rgb=12'h456;
                cy=demo_up ? 190-int'(demo_prog) : 142+int'(demo_prog);
                if(in_box(h,v,C2+80,cy-5,22,11))
                    rgb=(h<C2+82 || h>=C2+100 || v<cy-3 || v>cy+3) ?
                        12'hb86 : 12'he94;

                // Card 3: microphone; the sound waves follow the live volume.
                mdx=int'(h)-(C3+38);
                if(iabs(mdx)<=10 &&
                   ((v>=160 && v<=178) ||
                    (v>=150 && v<160 && mdx*mdx+(int'(v)-160)*(int'(v)-160)<=100) ||
                    (v>178 && v<=188 && mdx*mdx+(int'(v)-178)*(int'(v)-178)<=100)))
                    rgb=(v[1:0]==0 && v>153 && v<186 && iabs(mdx)<=7) ?
                        12'h789 : 12'hcde;
                mdy=int'(v)-176;
                d2=mdx*mdx+mdy*mdy;
                if(mdy>=0 && d2>=196 && d2<=272) rgb=12'h9ab;
                if(v>=166 && v<176 && iabs(mdx)>=14 && iabs(mdx)<=16) rgb=12'h9ab;
                if(in_box(h,v,C3+36,192,5,14)) rgb=12'h9ab;
                if(in_box(h,v,C3+26,205,25,4)) rgb=12'h9ab;
                mdx=int'(h)-(C3+52);
                mdy=int'(v)-169;
                d2=mdx*mdx+mdy*mdy;
                if(mdx>0 && iabs(mdy)<mdx) begin
                    if(d2>=256 && d2<=361) rgb=volume_count>=1 ? 12'h3dc : 12'h345;
                    if(d2>=625 && d2<=784) rgb=volume_count>=3 ? 12'h3dc : 12'h345;
                    if(d2>=1156 && d2<=1369) rgb=volume_count>=5 ? 12'hf73 : 12'h345;
                end

                // Card 4: aligned pipes carry the ball into the hole.
                lx=int'(h)-C4;
                cy=demo_path(lx);
                if(lx>=6 && lx<18 && iabs(int'(v)-200)<=5) rgb=12'h4df;
                if(lx>=18 && lx<92 && iabs(int'(v)-cy)<=6)
                    rgb=iabs(int'(v)-cy)<=3 ? 12'h5e8 : 12'h4b6;
                if(lx>=92 && lx<104 && iabs(int'(v)-200)<=14)
                    rgb=(lx>=95 && iabs(int'(v)-200)<=9) ? 12'h012 : 12'h0a4;
                if(lx>=36 && lx<44 && iabs(int'(v)-(140+lx-36))<=1) rgb=12'h5e8;
                if(lx>=44 && lx<=62 && iabs(int'(v)-(148-(lx-44)))<=1) rgb=12'h5e8;
                bx=C4+12+int'(demo_ball);
                case(ball_px(h,v,bx,demo_path(bx-C4),6))
                    2'd1: rgb=12'hc82;
                    2'd2: rgb=12'hff4;
                    2'd3: rgb=12'hfff;
                    default: ;
                endcase

                // Bottom row: BTNU / BTND.
                if(in_box(h,v,86,294,228,36))
                    rgb=(h<89 || h>=311 || v<297 || v>=327) ? 12'hfc5 : 12'h234;
                b=button_px(h,v,138,304);
                if(b!=0) rgb=b==1 ? 12'hfff : (anim[5] ? 12'hfc5 : 12'hda4);
                if(in_box(h,v,326,294,228,36))
                    rgb=(h<328 || h>=552 || v<296 || v>=328) ? 12'h567 : 12'h234;
                b=button_px(h,v,390,304); if(b!=0) rgb=b==1 ? 12'h789 : 12'h456;

                // Microphone test bar and the SW1/SW0 sensitivity switches.
                for(int k=0;k<7;k=k+1)
                    if(in_box(h,v,144+k*34,356,30,26))
                        rgb=k<volume_count ? (k>=4 ? 12'hf73 : 12'h3dc) : 12'h345;
                case(switch_px(h,v,403,358,12,26,sens_frame[1]))
                    2'd1: rgb=12'h9ab; 2'd2: rgb=12'h123; 2'd3: rgb=12'hdde;
                    default: ;
                endcase
                case(switch_px(h,v,427,358,12,26,sens_frame[0]))
                    2'd1: rgb=12'h9ab; 2'd2: rgb=12'h123; 2'd3: rgb=12'hdde;
                    default: ;
                endcase
            end else begin
                // ---------------- Game ----------------
                for(int i=0;i<3;i=i+1)
                    if(h>=24+i*23 && h<42+i*23 && v>=25 && v<43)
                        rgb=i<level_frame ? 12'hfd5 : 12'h456;
                if(h>=141 && h<440 && v>=20 && v<47) rgb=12'h456;
                if(h>=145 && h<440 &&
                   h<145+10'(seconds_frame)*10'd5 && v>=24 && v<43)
                    rgb=seconds_frame<=10 ? 12'hf54 : 12'hfd5;
                for(int i=0;i<8;i=i+1)
                    if(i<active_count && in_box(h,v,int'(status_x0)+i*15,27,12,16))
                        rgb=i==selected_frame ? 12'h2ef :
                            locked_frame[i] ? 12'h5e7 : 12'hb67;
                // Card above each pipe: switch number, live switch and arrow.
                for(int i=0;i<8;i=i+1) begin
                    if(i<active_count) begin
                        cx=int'(xlist_frame[i*10 +: 10])+int'(half_frame);
                        if(in_box(h,v,cx-24,80,48,44))
                            rgb=(h<cx-22 || h>=cx+22 || v<82 || v>=122) ?
                                (i==selected_frame ? 12'h2ef :
                                 locked_frame[i] ? 12'h3a6 : 12'h567) : 12'h234;
                        case(switch_px(h,v,cx-17,96,12,24,direction_frame[i]))
                            2'd1: rgb=12'h9ab;
                            2'd2: rgb=12'h123;
                            2'd3: rgb=direction_frame[i] ? 12'h7df : 12'hfd8;
                            default: ;
                        endcase
                        if(arrow_px(h,v,cx+8,97,6,22,1,direction_frame[i]))
                            rgb=direction_frame[i] ? 12'h7df : 12'hfd8;
                    end
                end
                // Source, goal, and faint target route.
                if(h<65 && iabs(int'(v)-int'(source_frame))<=int'(tube_frame)-2)
                    rgb=12'h4df;
                if(h>=552 && h<599 &&
                   iabs(int'(v)-int'(goal_frame))<=int'(tube_frame)-2) rgb=12'h6e6;
                if(h>=592 && h<625 &&
                   iabs(int'(v)-int'(goal_frame))<=int'(tube_frame)+15) rgb=12'h0a4;
                if(h>=600 && h<625 &&
                   iabs(int'(v)-int'(goal_frame))<=int'(tube_frame)+7) rgb=12'h012;
                for(int i=0;i<8;i=i+1) begin
                    px0=int'(xlist_frame[i*10 +: 10]);
                    if(i<active_count && h>=px0 && h<px0+int'(pipe_w)) begin
                        center_y=pipe_center(positions_frame[i*10 +: 10],7'(int'(h)-px0),
                                             mid_frame[i*2 +: 2],end_frame[i*2 +: 2],
                                             half_frame);
                        target_center=pipe_center(targets_frame[i*10 +: 10],
                                                  7'(int'(h)-px0),
                                                  mid_frame[i*2 +: 2],end_frame[i*2 +: 2],
                                                  half_frame);
                        tdy=int'(v)-int'(target_center);
                        dyc=int'(v)-int'(center_y);
                        if(h[2:1]!=0 && iabs(tdy)<=1) rgb=12'h567;
                        if(iabs(dyc)<=int'(tube_frame))
                            rgb=i==selected_frame ? 12'h2df : 12'h789;
                        if(iabs(dyc)<=int'(tube_frame)-int'(tube_frame>>2)-1)
                            rgb=locked_frame[i] ? 12'h174 : 12'h643;
                        if(iabs(dyc)<=int'(tube_frame>>1))
                            rgb=locked_frame[i] ? 12'h5e8 :
                                i==selected_frame ? 12'h4df : 12'he94;
                        if(dyc==-(int'(tube_frame)-1) || dyc==-(int'(tube_frame)-2))
                            rgb=12'habc;
                        if((h<px0+3 || h>=px0+int'(pipe_w)-3) &&
                           iabs(dyc)<=int'(tube_frame)+2)
                            rgb=locked_frame[i] ? 12'h4b6 :
                                i==selected_frame ? 12'h2ff : 12'hb86;
                    end
                end
                case(ball_px(h,v,ball_frame,ball_y,ballr_frame))
                    2'd1: rgb=12'hc82;
                    2'd2: rgb=12'hff4;
                    2'd3: rgb=12'hfff;
                    default: ;
                endcase
                if(state_frame==PREVIEW) begin
                    if(in_box(h,v,220,426,200,50))
                        rgb=(h<224 || h>=416 || v<430 || v>=472) ? 12'h2dc : 12'h234;
                end else begin
                    if(v>=439 && v<464 && h>=90 && h<552) rgb=12'h789;
                    if(v>=442 && v<461 && h>=94 && h<548) rgb=12'h123;
                    if(v>=442 && v<461 && h>=94 && h<94+10'(volume_count)*10'd64)
                        rgb=volume_count>=5 ? 12'hf73 : 12'h3dc;
                end
                if((state_frame==CLEAR || state_frame==LOST || state_frame==WON) &&
                   in_box(h,v,220,348,200,56))
                    rgb=(h<224 || h>=416 || v<352 || v>=400) ?
                        (state_frame==LOST ? 12'hf45 : 12'h2dc) : 12'h234;
                if(state_frame==PREVIEW) b=button_px(h,v,270,443);
                else if(state_frame==LOST) b=button_px(h,v,270,378);
                else if(state_frame==CLEAR || state_frame==WON) b=button_px(h,v,276,378);
                else b=2'd0;
                if(b!=0) rgb=b==1 ? 12'hfff : (anim[5] ? 12'hfc5 : 12'hda4);
            end
            if(font_on) rgb=font_color;
        end
    end
endmodule
