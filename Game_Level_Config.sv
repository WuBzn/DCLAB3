// Per-level layout. Levels use the first 4, 6, or 8 pipe slots from left to
// right; the slots are spread across the play area and scaled per level.
// Each pipe is two 45-degree halves: width = 2 * pipe_half, and one code step
// moves the centre line by pipe_half pixels (1 = down, 2 = up, 0 = level).
module Game_Level_Config(
    input  logic [1:0] level,
    output logic [5:0] time_limit,
    output logic [9:0] source_y, goal_y,
    output logic [79:0] target_positions, initial_positions,
    output logic [7:0] initial_locked,
    output logic [15:0] mid_codes, end_codes,
    output logic [79:0] pipe_x_list,   // left edge of each slot
    output logic [6:0]  pipe_half,     // half width = vertical step
    output logic [4:0]  tube_half,     // outer half thickness of the tube
    output logic [3:0]  ball_radius
);
    always_comb begin
        // Level 3 (default): eight 52-pixel pipes, 60-pixel pitch: x = 72..544.
        time_limit = 6'd60;
        source_y = 10'd290;
        goal_y = 10'd238;
        // Bit 0 / lowest slice is the leftmost pipe (SW14).
        target_positions = {10'd264,10'd238,10'd264,10'd264,
                            10'd290,10'd264,10'd264,10'd290};
        initial_positions = {10'd330,10'd170,10'd330,10'd170,
                             10'd325,10'd160,10'd335,10'd170};
        initial_locked = 8'b0000_0000;
        mid_codes = {2'd2,2'd0,2'd2,2'd2,2'd0,2'd1,2'd1,2'd0};
        end_codes = {2'd2,2'd1,2'd2,2'd0,2'd2,2'd1,2'd0,2'd2};
        pipe_x_list = {10'd492,10'd432,10'd372,10'd312,
                       10'd252,10'd192,10'd132,10'd72};
        pipe_half = 7'd26;
        tube_half = 5'd13;
        ball_radius = 4'd8;
        case (level)
            2'd1: begin
                // Four 104-pixel pipes, 120-pixel pitch: x = 78..542.
                time_limit = 6'd40;
                source_y = 10'd330;
                goal_y = 10'd226;
                target_positions = {10'd226,10'd226,10'd226,10'd226,
                                    10'd226,10'd278,10'd278,10'd330};
                initial_positions = {10'd226,10'd226,10'd226,10'd226,
                                     10'd330,10'd202,10'd336,10'd230};
                initial_locked = 8'b1111_0000;
                mid_codes = {2'd0,2'd0,2'd0,2'd0,2'd2,2'd0,2'd1,2'd2};
                end_codes = {2'd0,2'd0,2'd0,2'd0,2'd0,2'd2,2'd0,2'd2};
                pipe_x_list = {10'd700,10'd700,10'd700,10'd700,
                               10'd438,10'd318,10'd198,10'd78};
                pipe_half = 7'd52;
                tube_half = 5'd20;
                ball_radius = 4'd11;
            end
            2'd2: begin
                // Six 68-pixel pipes, 80-pixel pitch: x = 76..544.
                time_limit = 6'd50;
                source_y = 10'd204;
                goal_y = 10'd272;
                target_positions = {10'd272,10'd272,10'd238,10'd272,
                                    10'd272,10'd238,10'd238,10'd204};
                initial_positions = {10'd272,10'd272,10'd340,10'd182,
                                     10'd356,10'd150,10'd360,10'd310};
                initial_locked = 8'b1100_0000;
                mid_codes = {2'd0,2'd0,2'd1,2'd0,2'd1,2'd1,2'd2,2'd0};
                end_codes = {2'd0,2'd0,2'd1,2'd2,2'd0,2'd1,2'd0,2'd1};
                pipe_x_list = {10'd700,10'd700,10'd476,10'd396,
                               10'd316,10'd236,10'd156,10'd76};
                pipe_half = 7'd34;
                tube_half = 5'd16;
                ball_radius = 4'd9;
            end
            default: ;
        endcase
    end
endmodule
