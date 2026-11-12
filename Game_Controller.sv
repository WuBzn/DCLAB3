// Voice-controlled pipe puzzle. All game state stays in the 100 MHz domain.
// State codes are shared with Game_VGA.
module Game_Controller #(
    parameter int TICK_CYCLES = 5_000_000,   // at least 3
    parameter int TICKS_PER_SECOND = 20,
    // Pipes (including their outline) stay between the switch cards and
    // the VOICE panel.
    parameter int PLAY_TOP = 128,
    parameter int PLAY_BOTTOM = 412
)(
    input  logic        clk, rst, enable,
    input  logic        start_press, left_press, right_press, reset_press,
    input  logic [7:0]  pipe_direction, // bit 0 = leftmost = SW14
    input  logic [6:0]  volume_bar,
    input  logic [79:0] target_positions, initial_positions,
    input  logic [7:0]  initial_locked,
    input  logic [5:0]  time_limit,
    input  logic [15:0] mid_codes, end_codes,
    input  logic [6:0]  pipe_half,
    input  logic [4:0]  tube_half,
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
    logic load_pending, tick, pre_tick, tick_d;
    logic [9:0] pipe_y [0:7];
    // Per-pipe values that depend only on the level, registered so that the
    // 100 MHz move/lock logic starts from flip-flops.
    logic [9:0] target_q [0:7];
    logic [9:0] snap_lo_q [0:7];
    logic [9:0] snap_hi_q [0:7];
    logic [9:0] move_min_q [0:7];
    logic [9:0] move_max_q [0:7];
    // Stage 1: every cycle, a snapshot of the selected pipe and its inputs.
    logic [2:0] sel_s;
    logic [9:0] y_s, target_s, lo_s, hi_s, min_s, max_s;
    logic [3:0] step_s;
    logic up_s, locked_s;
    // Stage 2: on pre_tick, the move computed from the snapshot.
    logic move_en_q, move_snap_q;
    logic [2:0] move_sel_q;
    logic [9:0] move_y_q;
    logic [9:0] candidate_y;
    logic [7:0] active_mask;
    logic [3:0] step_pixels;
    logic snap_to_target, all_locked;
    integer j;

    assign pipe_positions = {pipe_y[7],pipe_y[6],pipe_y[5],pipe_y[4],
                             pipe_y[3],pipe_y[2],pipe_y[1],pipe_y[0]};
    assign tick = tick_count == TICK_CYCLES - 1;
    assign pre_tick = tick_count == TICK_CYCLES - 2;
    assign active_mask = level == 2'd1 ? 8'h0f :
                         level == 2'd2 ? 8'h3f : 8'hff;
    assign all_locked = (pipe_locked & active_mask) == active_mask;

    // The level only changes outside PLAY, and PLAY needs a further BTNU
    // press, so these registers are always settled while pipes move.
    always_ff @(posedge clk) begin
        for (j=0; j<8; j=j+1) begin
            target_q[j] <= target_positions[j*10 +: 10];
            snap_lo_q[j] <= target_positions[j*10 +: 10] - 10'd5;
            snap_hi_q[j] <= target_positions[j*10 +: 10] + 10'd5;
            // Limit the entrance height so the whole pipe stays visible.
            move_min_q[j] <= 10'(PLAY_TOP) + 10'(tube_half) + 10'd2 +
                             ((mid_codes[j*2 +: 2] == 2'd2 ||
                               end_codes[j*2 +: 2] == 2'd2) ?
                              10'(pipe_half) : 10'd0);
            move_max_q[j] <= 10'(PLAY_BOTTOM) - 10'(tube_half) - 10'd2 -
                             ((mid_codes[j*2 +: 2] == 2'd1 ||
                               end_codes[j*2 +: 2] == 2'd1) ?
                              10'(pipe_half) : 10'd0);
        end
    end

    always_comb begin
        if      (volume_bar[6]) step_pixels = 4'd7;
        else if (volume_bar[5]) step_pixels = 4'd6;
        else if (volume_bar[4]) step_pixels = 4'd5;
        else if (volume_bar[3]) step_pixels = 4'd4;
        else if (volume_bar[2]) step_pixels = 4'd3;
        else if (volume_bar[1]) step_pixels = 4'd2;
        else if (volume_bar[0]) step_pixels = 4'd1;
        else                    step_pixels = 4'd0;
    end

    // pipe_y and pipe_locked change only on a tick. With TICK_CYCLES >= 3
    // the snapshot used on pre_tick is taken after the previous tick, and the
    // move computed on pre_tick is still valid when it is applied on the tick.
    always_ff @(posedge clk) begin
        sel_s <= selected;
        y_s <= pipe_y[selected];
        up_s <= pipe_direction[selected];
        locked_s <= pipe_locked[selected];
        step_s <= step_pixels;
        target_s <= target_q[selected];
        lo_s <= snap_lo_q[selected];
        hi_s <= snap_hi_q[selected];
        min_s <= move_min_q[selected];
        max_s <= move_max_q[selected];
    end

    always_comb begin
        candidate_y = y_s;
        if (step_s != 0) begin
            if (up_s)
                candidate_y = y_s <= min_s + step_s ? min_s : y_s - step_s;
            else
                candidate_y = y_s >= max_s - step_s ? max_s : y_s + step_s;
        end
        snap_to_target = candidate_y >= lo_s && candidate_y <= hi_s;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) tick_d <= 1'b0;
        else     tick_d <= tick;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            move_en_q <= 1'b0;
            move_snap_q <= 1'b0;
            move_sel_q <= 0;
            move_y_q <= 0;
        end else if (pre_tick) begin
            move_en_q <= step_s != 0 && !locked_s;
            move_snap_q <= snap_to_target;
            move_sel_q <= sel_s;
            move_y_q <= snap_to_target ? target_s : candidate_y;
        end
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
            if (tick)
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
                    if (tick) begin
                        if (second_ticks == TICKS_PER_SECOND - 1) begin
                            second_ticks <= 0;
                            if (seconds_left != 0)
                                seconds_left <= seconds_left - 1'b1;
                        end else
                            second_ticks <= second_ticks + 1'b1;
                        if (move_en_q) begin
                            pipe_y[move_sel_q] <= move_y_q;
                            if (move_snap_q)
                                pipe_locked[move_sel_q] <= 1'b1;
                        end
                    end
                    // Judged one cycle after the tick from registered values;
                    // a pipe completed on the last tick still wins.
                    if (all_locked && !load_pending) begin
                        state <= ROLL;
                        ball_x <= 10'd48;
                    end else if (tick_d && seconds_left == 0) begin
                        state <= LOST;
                    end
                end
                ROLL: if (tick) begin
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
