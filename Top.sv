module Top #(
    parameter int MAX_WORDS = 781_250  // 16 seconds at 3.125 MHz, 64 bits/word
)(
    input  clk,
    input  locked,
    input  rst,
    input  data_in,
    input  record_press,
    input  play_pause_press,
    input  stop_press,
    input  [3:0] speed_select,
    output data_out,
    output recording,
    output playing,
    output paused,
    output recorded,
    output logic overflow,

    inout  [15:0] ddr2_dq,
    inout  [1 :0] ddr2_dqs_n,
    inout  [1 :0] ddr2_dqs_p,
    output [12:0] ddr2_addr,
    output [2 :0] ddr2_ba,
    output        ddr2_ras_n,
    output        ddr2_cas_n,
    output        ddr2_we_n,
    output        ddr2_ck_p,
    output        ddr2_ck_n,
    output        ddr2_cke,
    output        ddr2_cs_n,
    output [1 :0] ddr2_dm,
    output        ddr2_odt,
    input         clk_mem
);
    localparam int COUNT_BITS = $clog2(MAX_WORDS + 1);
    wire reset_n = locked && !rst;

    logic [23:0] mem_addr;
    logic [63:0] mem_d_to_ram;
    wire  [63:0] mem_d_from_ram;
    logic mem_wstrobe, mem_rstrobe;
    wire  mem_transaction_complete, mem_ready;

    ddr2_interface ddr2_interface0 (
        .clk_mem(clk_mem), .rst_n(reset_n),
        .ddr2_addr(ddr2_addr), .ddr2_ba(ddr2_ba),
        .ddr2_cas_n(ddr2_cas_n), .ddr2_ck_n(ddr2_ck_n),
        .ddr2_ck_p(ddr2_ck_p), .ddr2_cke(ddr2_cke),
        .ddr2_ras_n(ddr2_ras_n), .ddr2_we_n(ddr2_we_n),
        .ddr2_dq(ddr2_dq), .ddr2_dqs_n(ddr2_dqs_n),
        .ddr2_dqs_p(ddr2_dqs_p), .ddr2_cs_n(ddr2_cs_n),
        .ddr2_dm(ddr2_dm), .ddr2_odt(ddr2_odt),
        .cpu_clk(clk), .addr(mem_addr), .data_in(mem_d_to_ram),
        .data_out(mem_d_from_ram), .rstrobe(mem_rstrobe),
        .wstrobe(mem_wstrobe),
        .transaction_complete(mem_transaction_complete), .ready(mem_ready)
    );

    typedef enum logic [2:0] {
        EMPTY, RECORD, DRAIN, READY, PREFILL, PLAY, PAUSE
    } mode_t;
    typedef enum logic [1:0] {
        MEM_IDLE, WRITE_WAIT, READ_WAIT
    } mem_state_t;

    mode_t mode;
    mem_state_t mem_state;

    logic [63:0] capture_shift, write_word;
    logic [5 :0] capture_bit;
    logic write_pending, stop_requested;
    logic [COUNT_BITS-1:0] recorded_words;
    logic [23:0] write_addr;

    logic [63:0] play_word, next_word;
    // play_bit == 64 means the current word has been consumed and the next
    // DDR2 read has not arrived yet.
    logic [6:0] play_bit;
    logic next_valid;
    logic [COUNT_BITS-1:0] played_words, fetched_words;
    logic [23:0] read_addr;
    logic silence_bit;
    logic [3:0] active_speed, repeat_count, ones_accum;
    logic [3:0] speed_factor, group_size, ones_in_group;
    logic [4:0] density_sum;
    logic [7:0] bit_end;
    logic group_ready, final_word, speed_changed, output_bit;
    logic play_loaded;
    integer bit_index;

    // SW[3] selects slow playback; SW[2:0] selects 1x through 8x.
    // The 1x setting works the same for either direction.
    assign speed_factor = {1'b0, speed_select[2:0]} + 4'd1;
    assign speed_changed = speed_select != active_speed;
    assign final_word = played_words == recorded_words - 1'b1;
    assign group_size = speed_select[3] ? 4'd1 : speed_factor;
    assign bit_end = {1'b0, play_bit} + {4'b0, group_size};
    assign group_ready = play_bit < 7'd64 &&
                         (bit_end <= 8'd64 || final_word || next_valid);

    // For fast playback, each output bit consumes n input bits. Keep the
    // leftover one-count across groups (including 64-bit word boundaries).
    always_comb begin
        ones_in_group = 0;
        for (integer i = 0; i < 8; i = i + 1) begin
            bit_index = play_bit + i;
            if (i < group_size && (bit_index < 64 || !final_word)) begin
                if (bit_index < 64)
                    ones_in_group = ones_in_group + play_word[63 - bit_index];
                else
                    ones_in_group = ones_in_group + next_word[127 - bit_index];
            end
        end
    end
    assign density_sum = {1'b0, speed_changed ? 4'd0 : ones_accum} +
                         {1'b0, ones_in_group};
    assign output_bit = speed_select[3] || speed_factor == 4'd1 ?
                        play_word[7'd63 - play_bit] :
                        (density_sum >= {1'b0, speed_factor});

    wire capture_full = mode == RECORD && capture_bit == 6'd63;
    wire issue_write = mem_state == MEM_IDLE && mem_ready &&
                       (mode == RECORD || mode == DRAIN) && write_pending;

    assign recording = mode == RECORD || mode == DRAIN;
    assign playing   = mode == PLAY;
    assign paused    = mode == PAUSE;
    assign recorded  = recorded_words != 0 && !recording;
    // 50% PDM density while idle/paused keeps the audio input centered.
    assign data_out = playing && group_ready ? output_bit : silence_bit;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            mode <= EMPTY;
            mem_state <= MEM_IDLE;
            mem_addr <= 0;
            mem_d_to_ram <= 0;
            mem_wstrobe <= 0;
            mem_rstrobe <= 0;
            capture_shift <= 0;
            write_word <= 0;
            capture_bit <= 0;
            write_pending <= 0;
            stop_requested <= 0;
            recorded_words <= 0;
            write_addr <= 0;
            play_word <= 0;
            next_word <= 0;
            play_bit <= 0;
            next_valid <= 0;
            play_loaded <= 0;
            active_speed <= 0;
            repeat_count <= 0;
            ones_accum <= 0;
            played_words <= 0;
            fetched_words <= 0;
            read_addr <= 0;
            silence_bit <= 0;
            overflow <= 0;
        end else begin
            mem_wstrobe <= 0;
            mem_rstrobe <= 0;
            silence_bit <= ~silence_bit;
            active_speed <= speed_select;
            if (speed_changed) begin
                repeat_count <= 0;
                ones_accum <= 0;
            end

            // A memory request owns its address/data until completion.
            case (mem_state)
                MEM_IDLE: begin
                    if (issue_write) begin
                        mem_addr <= write_addr;
                        mem_d_to_ram <= write_word;
                        mem_wstrobe <= 1;
                        mem_state <= WRITE_WAIT;
                    end else if (mem_ready &&
                                 (mode == PREFILL || mode == PLAY || mode == PAUSE) &&
                                 fetched_words < recorded_words && !next_valid) begin
                        mem_addr <= read_addr;
                        mem_rstrobe <= 1;
                        mem_state <= READ_WAIT;
                    end
                end
                WRITE_WAIT: if (mem_transaction_complete) begin
                    write_addr <= write_addr + 24'd2; // 128-bit MIG burst
                    mem_state <= MEM_IDLE;
                end
                READ_WAIT: if (mem_transaction_complete) begin
                    mem_state <= MEM_IDLE;
                    if (mode == PREFILL || mode == PLAY || mode == PAUSE) begin
                        read_addr <= read_addr + 24'd2;
                        fetched_words <= fetched_words + 1'b1;
                        if (mode == PREFILL && !play_loaded) begin
                            play_word <= mem_d_from_ram;
                            play_loaded <= 1;
                            if (recorded_words == 1)
                                mode <= PLAY;
                        end else begin
                            next_word <= mem_d_from_ram;
                            next_valid <= 1;
                            if (mode == PREFILL)
                                mode <= PLAY;
                        end
                    end
                end
                default: mem_state <= MEM_IDLE;
            endcase

            // The microphone keeps shifting while DDR2 writes the previous word.
            if (issue_write && !capture_full)
                write_pending <= 0;

            case (mode)
                EMPTY, READY: begin
                    if (record_press && mem_ready && mem_state == MEM_IDLE) begin
                        mode <= RECORD;
                        capture_shift <= 0;
                        capture_bit <= 0;
                        write_pending <= 0;
                        stop_requested <= 0;
                        recorded_words <= 0;
                        write_addr <= 0;
                        overflow <= 0;
                        next_valid <= 0;
                    end else if (mode == READY && play_pause_press &&
                                 mem_state == MEM_IDLE && recorded_words != 0) begin
                        mode <= PREFILL;
                        read_addr <= 0;
                        fetched_words <= 0;
                        played_words <= 0;
                        play_bit <= 0;
                        next_valid <= 0;
                        play_loaded <= 0;
                        repeat_count <= 0;
                        ones_accum <= 0;
                    end
                end
                RECORD: begin
                    capture_shift <= {capture_shift[62:0], data_in};
                    capture_bit <= capture_bit + 1'b1;
                    if (record_press || stop_press)
                        stop_requested <= 1;

                    if (capture_full) begin
                        if (write_pending && !issue_write) begin
                            overflow <= 1;
                            mode <= DRAIN;
                        end else begin
                            write_word <= {capture_shift[62:0], data_in};
                            write_pending <= 1;
                            recorded_words <= recorded_words + 1'b1;
                            if (stop_requested || record_press || stop_press ||
                                recorded_words == MAX_WORDS - 1)
                                mode <= DRAIN;
                        end
                    end
                end
                DRAIN: if (!write_pending && mem_state == MEM_IDLE)
                    mode <= READY;

                PREFILL: if (stop_press)
                    mode <= READY;

                PLAY: begin
                    if (stop_press) begin
                        mode <= READY;
                    end else begin
                        // Consume the bit already presented to the audio output
                        // before pausing, so resume does not play it twice.
                        if (play_pause_press)
                            mode <= PAUSE;
                        if (play_bit == 7'd64) begin
                            if (next_valid) begin
                                play_word <= next_word;
                                next_valid <= 0;
                                played_words <= played_words + 1'b1;
                                play_bit <= 0;
                            end else
                                overflow <= 1;
                        end else if (group_ready) begin
                            if (speed_select[3] && speed_factor > 4'd1 &&
                                (speed_changed || repeat_count < speed_factor - 1'b1)) begin
                                repeat_count <= (speed_changed ? 4'd0 : repeat_count) + 1'b1;
                            end else begin
                                repeat_count <= 0;
                                if (!speed_select[3] && speed_factor != 4'd1)
                                    ones_accum <= density_sum >= {1'b0, speed_factor} ?
                                                  density_sum - {1'b0, speed_factor} : density_sum;
                                else
                                    ones_accum <= 0;
                                if (final_word && bit_end >= 8'd64) begin
                                    mode <= READY;
                                end else if (bit_end >= 8'd64) begin
                                    if (next_valid) begin
                                        play_word <= next_word;
                                        next_valid <= 0;
                                        played_words <= played_words + 1'b1;
                                        play_bit <= bit_end - 8'd64;
                                    end else begin
                                        play_bit <= 7'd64;
                                    end
                                end else begin
                                    play_bit <= bit_end[6:0];
                                end
                            end
                        end else begin
                            overflow <= 1; // DDR2 could not keep up with playback.
                        end
                    end
                end
                PAUSE: begin
                    if (stop_press)
                        mode <= READY;
                    else if (play_pause_press)
                        mode <= PLAY;
                end
                default: mode <= EMPTY;
            endcase
        end
    end
endmodule
