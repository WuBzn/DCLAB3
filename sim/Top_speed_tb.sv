`timescale 1ns/1ps

module Top_speed_tb;
    logic clk = 0, rst = 1, locked = 1;
    logic data_in = 0, record_press = 0, play_pause_press = 0, stop_press = 0;
    logic [3:0] speed_select = 0;
    logic reverse_select = 0;
    wire data_out, recording, playing, paused, recorded, overflow, reverse_mode;
    wire [4:0] display_seconds;
    logic [63:0] words [0:3];
    logic expected [0:2047];
    integer expected_len, sampled, case_number;
    integer source_length = 256;
    bit case_reverse;
    bit checking = 0;

    always #5 clk = ~clk;

    // A short display second keeps time-boundary checks fast in simulation.
    Top #(.MAX_WORDS(4), .AUDIO_BITS_PER_SECOND(64)) dut (
        .clk(clk), .clk_mem(clk), .locked(locked), .rst(rst),
        .data_in(data_in), .record_press(record_press),
        .play_pause_press(play_pause_press), .stop_press(stop_press),
        .speed_select(speed_select), .reverse_select(reverse_select),
        .data_out(data_out), .reverse_mode(reverse_mode),
        .recording(recording), .playing(playing), .paused(paused),
        .recorded(recorded), .overflow(overflow),
        .display_seconds(display_seconds)
    );

    // The microphone changes data on the falling edge of its 3.125 MHz clock.
    integer mic_bit = 0;
    always @(negedge clk)
        if (recording && mic_bit < 256) begin
            data_in = words[mic_bit / 64][63 - (mic_bit % 64)];
            mic_bit = mic_bit + 1;
        end

    always @(negedge clk)
        if (checking && playing && dut.group_ready) begin
            if (sampled >= expected_len || data_out !== expected[sampled])
                $fatal(1, "reverse=%0d speed=%0d output[%0d]=%b expected=%b",
                       case_reverse, case_number, sampled, data_out,
                       expected[sampled]);
            sampled = sampled + 1;
        end

    task automatic pulse_record;
        begin
            @(negedge clk) record_press = 1;
            @(negedge clk) record_press = 0;
        end
    endtask

    task automatic pulse_play;
        begin
            @(negedge clk) play_pause_press = 1;
            @(negedge clk) play_pause_press = 0;
        end
    endtask

    task automatic pulse_stop;
        begin
            @(negedge clk) stop_press = 1;
            @(negedge clk) stop_press = 0;
        end
    endtask

    function automatic bit source_bit(input integer index,
                                      input bit reverse_direction);
        integer position;
        begin
            position = reverse_direction ? source_length - 1 - index : index;
            source_bit = words[position / 64][63 - (position % 64)];
        end
    endfunction

    task automatic make_expected(input integer code,
                                 input bit reverse_direction);
        integer factor, accum, ones, i, j;
        begin
            factor = (code % 8) + 1;
            expected_len = 0;
            accum = 0;
            if (code >= 8) begin
                for (i = 0; i < source_length; i = i + 1)
                    for (j = 0; j < factor; j = j + 1) begin
                        expected[expected_len] = source_bit(i, reverse_direction);
                        expected_len = expected_len + 1;
                    end
            end else begin
                for (i = 0; i < source_length; i = i + factor) begin
                    ones = 0;
                    for (j = 0; j < factor && i + j < source_length; j = j + 1)
                        ones = ones + source_bit(i+j, reverse_direction);
                    accum = accum + ones;
                    expected[expected_len] = (accum >= factor);
                    if (accum >= factor) accum = accum - factor;
                    expected_len = expected_len + 1;
                end
            end
        end
    endtask

    task automatic run_case(input integer code, input bit reverse_direction);
        begin
            speed_select = code;
            case_number = code;
            case_reverse = reverse_direction;
            sampled = 0;
            make_expected(code, reverse_direction);
            checking = 1;
            pulse_play();
            wait (playing);
            if (reverse_mode !== reverse_direction)
                $fatal(1, "Playback direction changed after recording");
            if (code == 0) begin
                reverse_select = reverse_direction;
                repeat (9) @(negedge clk);
                reverse_select = !reverse_direction;
                if (reverse_direction && source_length == 256) begin
                    wait (sampled >= 65);
                    if (display_seconds != 3)
                        $fatal(1, "Reverse source seconds did not count down");
                end
            end
            wait (!playing);
            checking = 0;
            #1; // Let the READY display mux settle after the final bit.
            if (sampled != expected_len || overflow || !recorded ||
                dut.play_seconds != (reverse_direction ? 0 : source_length / 64) ||
                display_seconds != source_length / 64)
                $fatal(1, "reverse=%0d speed=%0d samples=%0d expected=%0d play_s=%0d record_s=%0d display_s=%0d mode=%0d overflow=%b",
                       reverse_direction, code, sampled, expected_len, dut.play_seconds,
                       dut.record_seconds, display_seconds, dut.mode, overflow);
            repeat (3) @(negedge clk);
        end
    endtask

    integer mode_code, held_bit, held_repeat;
    initial begin
        words[0] = 64'hA35C_F00D_1234_5678;
        words[1] = 64'h69E1_0B5A_C7D2_4F80;
        words[2] = 64'hF0F0_00FF_AA55_9988;
        words[3] = 64'h1234_5678_9ABC_DEF0;
        repeat (3) @(negedge clk);
        rst = 0;
        pulse_record();
        wait (recorded && !recording);
        if (mic_bit != 256 || dut.recorded_words != 4 ||
            display_seconds != 4 || overflow)
            $fatal(1, "Recording setup failed");
        reverse_select = 1; // SW4 changes after recording; playback stays forward.
        for (mode_code = 0; mode_code < 16; mode_code = mode_code + 1)
            run_case(mode_code, 0);

        speed_select = 11; // 1/4x: pause in the middle of a repeated sample.
        case_number = 11;
        sampled = 0;
        make_expected(11, 0);
        checking = 1;
        pulse_play();
        wait (sampled >= 301);
        pulse_play();
        if (!paused) $fatal(1, "Pause was not entered");
        if (display_seconds != 1)
            $fatal(1, "Paused at wrong source second: %0d", display_seconds);
        held_bit = dut.play_bit;
        held_repeat = dut.repeat_count;
        repeat (12) @(negedge clk);
        if (dut.play_bit != held_bit || dut.repeat_count != held_repeat ||
            display_seconds != 1)
            $fatal(1, "Playback advanced while paused");
        pulse_play();
        wait (!playing);
        checking = 0;
        if (sampled != expected_len || overflow || dut.play_seconds != 4)
            $fatal(1, "Pause/resume failed: samples=%0d expected=%0d",
                   sampled, expected_len);

        speed_select = 0;
        pulse_play();
        wait (playing);
        repeat (12) @(negedge clk);
        speed_select = 7;  // Change to 8x during playback.
        repeat (5) @(negedge clk);
        speed_select = 15; // Change to 1/8x during playback.
        wait (!playing);
        if (overflow || !recorded)
            $fatal(1, "Live speed change did not finish cleanly");

        // A new recording replaces both the data and its latched direction.
        mic_bit = 0;
        reverse_select = 1;
        pulse_record();
        wait (recorded && !recording);
        if (mic_bit != 256 || dut.recorded_words != 4 || !reverse_mode || overflow)
            $fatal(1, "Reverse recording setup failed");
        reverse_select = 0; // SW4 must no longer affect this recording.
        for (mode_code = 0; mode_code < 16; mode_code = mode_code + 1)
            run_case(mode_code, 1);

        speed_select = 11; // Pause during a repeated bit in reverse.
        case_number = 11;
        case_reverse = 1;
        sampled = 0;
        make_expected(11, 1);
        checking = 1;
        pulse_play();
        wait (sampled >= 301);
        pulse_play();
        if (!paused || display_seconds != 3)
            $fatal(1, "Reverse pause entered at wrong position");
        held_bit = dut.play_bit;
        held_repeat = dut.repeat_count;
        reverse_select = 1;
        repeat (12) @(negedge clk);
        if (dut.play_bit != held_bit || dut.repeat_count != held_repeat ||
            display_seconds != 3 || !reverse_mode)
            $fatal(1, "Reverse playback advanced or direction changed while paused");
        pulse_play();
        wait (!playing);
        checking = 0;
        if (sampled != expected_len || overflow || dut.play_seconds != 0)
            $fatal(1, "Reverse pause/resume failed");

        speed_select = 0;
        pulse_play();
        wait (playing);
        repeat (12) @(negedge clk);
        speed_select = 7;  // Change to 8x during reverse playback.
        repeat (5) @(negedge clk);
        speed_select = 15; // Then change to 1/8x.
        wait (!playing);
        if (overflow || !recorded || !reverse_mode || dut.play_seconds != 0)
            $fatal(1, "Reverse live speed change did not finish cleanly");

        // Stop a new recording after just one word. Reverse prefill must not
        // request an address before zero or wait for a second word.
        mic_bit = 0;
        reverse_select = 1;
        pulse_record();
        wait (mic_bit >= 16);
        pulse_stop();
        wait (recorded && !recording);
        if (mic_bit < 64 || mic_bit >= 128 || dut.recorded_words != 1 ||
            !reverse_mode || overflow)
            $fatal(1, "Single-word reverse recording setup failed: bits=%0d words=%0d reverse=%b overflow=%b",
                   mic_bit, dut.recorded_words, reverse_mode, overflow);
        source_length = 64;
        reverse_select = 0;
        run_case(0, 1);
        run_case(5, 1);  // Partial final fast group.
        run_case(15, 1);

        $display("PASS: forward/reverse speeds, direction latch, pause/resume, countdown, one-word edge");
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "Timeout at reverse=%0d speed=%0d samples=%0d",
               case_reverse, case_number, sampled);
    end
endmodule

// Transaction-level DDR2 model: one request at a time, with a short delay.
module ddr2_interface (
    input clk_mem, rst_n,
    inout [15:0] ddr2_dq,
    inout [1:0] ddr2_dqs_n, ddr2_dqs_p,
    output [12:0] ddr2_addr,
    output [2:0] ddr2_ba,
    output ddr2_ras_n, ddr2_cas_n, ddr2_we_n,
           ddr2_ck_p, ddr2_ck_n, ddr2_cke, ddr2_cs_n,
    output [1:0] ddr2_dm,
    output ddr2_odt,
    input cpu_clk,
    input [23:0] addr,
    input [63:0] data_in,
    output logic [63:0] data_out,
    input rstrobe, wstrobe,
    output logic transaction_complete,
    output ready
);
    logic [63:0] memory [0:3];
    logic pending;
    assign ready = rst_n;
    assign {ddr2_addr, ddr2_ba, ddr2_ras_n, ddr2_cas_n,
            ddr2_we_n, ddr2_ck_p, ddr2_ck_n, ddr2_cke,
            ddr2_cs_n, ddr2_dm, ddr2_odt} = '0;
    always @(posedge cpu_clk or negedge rst_n) begin
        if (!rst_n) begin
            pending <= 0;
            transaction_complete <= 0;
            data_out <= 0;
        end else begin
            transaction_complete <= pending;
            pending <= 0;
            if (rstrobe || wstrobe) begin
                if (pending || (rstrobe && wstrobe) || addr[0] || addr > 6)
                    $fatal(1, "Invalid DDR2 request");
                if (wstrobe) memory[addr >> 1] <= data_in;
                else data_out <= memory[addr >> 1];
                pending <= 1;
            end
        end
    end
endmodule
