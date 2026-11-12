// Voice-controlled pipe puzzle. All game state stays in the 100 MHz domain.
// State codes are shared with Game_VGA.
module Game_Controller #(
    parameter int TICK_CYCLES = 5_000_000,
    parameter int TICKS_PER_SECOND = 20
)(
    input  logic        clk, rst, enable,
    input  logic        start_press, left_press, right_press, reset_press,
    input  logic [7:0]  pipe_direction, // bit 0 = leftmost = SW14
    input  logic [6:0]  volume_bar,
    input  logic [79:0] target_positions, initial_positions,
    input  logic [7:0]  initial_locked,
    input  logic [5:0]  time_limit,
    output logic [2:0]  state,
    output logic [1:0]  level,
    output logic [2:0]  selected,
    output logic [5:0]  seconds_left,
    output logic [7:0]  pipe_locked,
    output logic [79:0] pipe_positions,
    output logic [9:0]  ball_x
);
    localparam logic [2:0] OFF=0, INSTRUCTIONS=1, PREVIEW=2,
                           PLAY=3, ROLL=4, CLEAR=5, LOST=6, WON=7;
    localparam int TICK_BITS = $clog2(TICK_CYCLES + 1);
    localparam int SEC_BITS = $clog2(TICKS_PER_SECOND + 1);
    logic [TICK_BITS-1:0] tick_count;
    logic [SEC_BITS-1:0] second_ticks;
    logic load_pending;
    logic [9:0] pipe_y [0:7];
    logic [9:0] selected_y, target_y, candidate_y;
    logic [7:0] next_locked, active_mask;
    logic [3:0] step_pixels;
    logic selected_up, snap_to_target;
    integer j;

    assign pipe_positions = {pipe_y[7],pipe_y[6],pipe_y[5],pipe_y[4],
                             pipe_y[3],pipe_y[2],pipe_y[1],pipe_y[0]};
    assign selected_up = pipe_direction[selected];
    assign selected_y = pipe_y[selected];
    assign active_mask = level == 2'd1 ? 8'h0f :
                         level == 2'd2 ? 8'h3f : 8'hff;

    always_comb begin
        target_y = target_positions[selected*10 +: 10];
        if      (volume_bar[6]) step_pixels = 4'd7;
        else if (volume_bar[5]) step_pixels = 4'd6;
        else if (volume_bar[4]) step_pixels = 4'd5;
        else if (volume_bar[3]) step_pixels = 4'd4;
        else if (volume_bar[2]) step_pixels = 4'd3;
        else if (volume_bar[1]) step_pixels = 4'd2;
        else if (volume_bar[0]) step_pixels = 4'd1;
        else                    step_pixels = 4'd0;

        candidate_y = selected_y;
        if (step_pixels != 0) begin
            if (selected_up)
                candidate_y = selected_y <= 10'd150 + step_pixels ?
                              10'd150 : selected_y - step_pixels;
            else
                candidate_y = selected_y >= 10'd350 - step_pixels ?
                              10'd350 : selected_y + step_pixels;
        end
        snap_to_target = candidate_y >= target_y - 10'd5 &&
                         candidate_y <= target_y + 10'd5;
        next_locked = pipe_locked;
        if (step_pixels != 0 && !pipe_locked[selected] && snap_to_target)
            next_locked[selected] = 1'b1;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= OFF;
            level <= 2'd1;
            selected <= 0;
            seconds_left <= 6'd40;
            second_ticks <= 0;
            tick_count <= 0;
            load_pending <= 0;
            pipe_locked <= 8'hf0;
            for (j=0; j<8; j=j+1)
                pipe_y[j] <= 10'd240;
            ball_x <= 10'd48;
        end else if (!enable) begin
            state <= OFF;
            level <= 2'd1;
            selected <= 0;
            seconds_left <= 6'd40;
            second_ticks <= 0;
            tick_count <= 0;
            load_pending <= 0;
            pipe_locked <= 8'hf0;
            for (j=0; j<8; j=j+1)
                pipe_y[j] <= 10'd240;
            ball_x <= 10'd48;
        end else if (reset_press) begin
            state <= INSTRUCTIONS;
            level <= 2'd1;
            selected <= 0;
            second_ticks <= 0;
            tick_count <= 0;
            load_pending <= 1;
            ball_x <= 10'd48;
        end else begin
            if (tick_count == TICK_CYCLES - 1)
                tick_count <= 0;
            else
                tick_count <= tick_count + 1'b1;
            if (load_pending) begin
                for (j=0; j<8; j=j+1)
                    pipe_y[j] <= initial_positions[j*10 +: 10];
                pipe_locked <= initial_locked;
                seconds_left <= time_limit;
                second_ticks <= 0;
                ball_x <= 10'd48;
                load_pending <= 0;
            end
            case (state)
                OFF: begin
                    state <= INSTRUCTIONS;
                    level <= 2'd1;
                    selected <= 0;
                    load_pending <= 1;
                end
                INSTRUCTIONS: if (start_press && !load_pending) begin
                    state <= PREVIEW;
                    selected <= 0;
                end
                PREVIEW: if (start_press && !load_pending) begin
                    state <= PLAY;
                    tick_count <= 0;
                    second_ticks <= 0;
                end
                PLAY: begin
                    if (left_press && selected != 0)
                        selected <= selected - 1'b1;
                    else if (right_press &&
                             selected < (level == 2'd1 ? 3'd3 :
                                         level == 2'd2 ? 3'd5 : 3'd7))
                        selected <= selected + 1'b1;
                    if (tick_count == TICK_CYCLES - 1) begin
                        if (second_ticks == TICKS_PER_SECOND - 1) begin
                            second_ticks <= 0;
                            if (seconds_left != 0)
                                seconds_left <= seconds_left - 1'b1;
                        end else
                            second_ticks <= second_ticks + 1'b1;
                        if (step_pixels != 0 && !pipe_locked[selected]) begin
                            pipe_y[selected] <= snap_to_target ? target_y : candidate_y;
                            pipe_locked <= next_locked;
                        end
                        if ((next_locked & active_mask) == active_mask) begin
                            state <= ROLL;
                            ball_x <= 10'd48;
                        end else if (seconds_left == 1 &&
                                     second_ticks == TICKS_PER_SECOND - 1) begin
                            state <= LOST;
                            seconds_left <= 0;
                        end
                    end
                end
                ROLL: if (tick_count == TICK_CYCLES - 1) begin
                    if (ball_x >= 10'd588) begin
                        ball_x <= 10'd600;
                        state <= level == 2'd3 ? WON : CLEAR;
                    end else
                        ball_x <= ball_x + 10'd12;
                end
                CLEAR: if (start_press) begin
                    level <= level + 1'b1;
                    state <= PREVIEW;
                    selected <= 0;
                    load_pending <= 1;
                end
                LOST: if (start_press) begin
                    state <= PREVIEW;
                    selected <= 0;
                    load_pending <= 1;
                end
                WON: if (start_press) begin
                    state <= INSTRUCTIONS;
                    level <= 2'd1;
                    selected <= 0;
                    load_pending <= 1;
                end
                default: state <= OFF;
            endcase
        end
    end
endmodule
