// Eight pipe slots; levels use the first 4, 6, or 8 from left to right.
// Each pipe is 52 pixels wide, with two 26-pixel slopes.
module Game_Level_Config(
    input  logic [1:0] level,
    output logic [5:0] time_limit,
    output logic [9:0] source_y, goal_y,
    output logic [79:0] target_positions, initial_positions,
    output logic [7:0] initial_locked,
    output logic [15:0] mid_codes, end_codes
);
    always_comb begin
        time_limit = 6'd40;
        source_y = 10'd264;
        goal_y = 10'd212;
        // Bit 0 / lowest slice is the leftmost pipe (SW14).
        target_positions = {10'd212,10'd238,10'd238,10'd212,
                            10'd212,10'd238,10'd238,10'd264};
        initial_positions = {10'd212,10'd238,10'd238,10'd212,
                             10'd320,10'd175,10'd330,10'd190};
        initial_locked = 8'b1111_0000;
        mid_codes = {2'd1,2'd0,2'd2,2'd1,2'd2,2'd0,2'd1,2'd2};
        end_codes = {2'd0,2'd2,2'd0,2'd1,2'd0,2'd2,2'd0,2'd2};
        case (level)
            2'd2: begin
                time_limit = 6'd50;
                source_y = 10'd208;
                goal_y = 10'd260;
                target_positions = {10'd260,10'd260,10'd234,10'd260,
                                    10'd260,10'd234,10'd234,10'd208};
                initial_positions = {10'd260,10'd260,10'd160,10'd330,
                                     10'd175,10'd330,10'd165,10'd315};
                initial_locked = 8'b1100_0000;
                mid_codes = {2'd1,2'd2,2'd1,2'd0,2'd1,2'd1,2'd2,2'd0};
                end_codes = {2'd0,2'd0,2'd1,2'd2,2'd0,2'd1,2'd0,2'd1};
            end
            2'd3: begin
                time_limit = 6'd60;
                source_y = 10'd290;
                goal_y = 10'd238;
                target_positions = {10'd264,10'd238,10'd264,10'd264,
                                    10'd290,10'd264,10'd264,10'd290};
                initial_positions = {10'd330,10'd170,10'd330,10'd165,
                                     10'd325,10'd160,10'd335,10'd170};
                initial_locked = 8'b0000_0000;
                mid_codes = {2'd2,2'd0,2'd2,2'd2,2'd0,2'd1,2'd1,2'd0};
                end_codes = {2'd2,2'd1,2'd2,2'd0,2'd2,2'd1,2'd0,2'd2};
            end
            default: ;
        endcase
    end
endmodule
