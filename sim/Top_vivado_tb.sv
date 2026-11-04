`timescale 1ps/1ps

// Uses the project's Clock Wizard, MIG, and MIG-generated DDR2 model.
module Top_vivado_tb;
    localparam logic [63:0] WORD0 = 64'hA35C_F00D_1234_5678;
    localparam logic [63:0] WORD1 = 64'h69E1_0B5A_C7D2_4F80;

    logic clk100 = 0;
    logic btnc = 1;
    logic btnu = 0;
    logic btnr = 0;
    logic btnd = 0;
    logic m_data = 0;
    tri1 aud_pwm; // The board pulls the open-drain audio pin high.
    wire aud_sd, m_lrsel;
    wire [15:0] led;

    wire [12:0] ddr2_addr;
    wire [2:0] ddr2_ba;
    wire ddr2_ras_n, ddr2_cas_n, ddr2_we_n;
    wire ddr2_ck_p, ddr2_ck_n, ddr2_cke, ddr2_cs_n;
    wire [1:0] ddr2_dm;
    wire ddr2_odt;
    wire [15:0] ddr2_dq;
    wire [1:0] ddr2_dqs_p, ddr2_dqs_n;

    always #5_000 clk100 = ~clk100;

    NEXYS_A7 #(.DEBOUNCE_CYCLES(4), .MAX_WORDS(4)) dut (
        .CLK100MHZ(clk100), .SW(16'b0), .LED(led),
        .BTNC(btnc), .BTNU(btnu), .BTNR(btnr), .BTND(btnd),
        .M_DATA(m_data), .M_LRSEL(m_lrsel),
        .AUD_PWM(aud_pwm), .AUD_SD(aud_sd),
        .ddr2_ras_n(ddr2_ras_n), .ddr2_cas_n(ddr2_cas_n),
        .ddr2_we_n(ddr2_we_n), .ddr2_ck_p(ddr2_ck_p),
        .ddr2_ck_n(ddr2_ck_n), .ddr2_cke(ddr2_cke),
        .ddr2_cs_n(ddr2_cs_n), .ddr2_dm(ddr2_dm),
        .ddr2_odt(ddr2_odt), .ddr2_dq(ddr2_dq),
        .ddr2_dqs_p(ddr2_dqs_p), .ddr2_dqs_n(ddr2_dqs_n)
    );

    ddr2_model memory (
        .ck(ddr2_ck_p), .ck_n(ddr2_ck_n),
        .cke(ddr2_cke), .cs_n(ddr2_cs_n),
        .ras_n(ddr2_ras_n), .cas_n(ddr2_cas_n),
        .we_n(ddr2_we_n), .dm_rdqs(ddr2_dm),
        .ba(ddr2_ba), .addr(ddr2_addr),
        .dq(ddr2_dq), .dqs(ddr2_dqs_p),
        .dqs_n(ddr2_dqs_n), .rdqs_n(), .odt(ddr2_odt)
    );

    initial #200_000 btnc = 0;

    integer mic_bits = 0;
    always @(negedge dut.M_CLK) begin
        if (dut.recording && mic_bits < 128) begin
            m_data = mic_bits < 64 ? WORD0[63-mic_bits] : WORD1[127-mic_bits];
            mic_bits = mic_bits + 1;
        end
    end

    integer requests = 0;
    integer completions = 0;
    logic pending = 0;
    logic pending_read;
    logic [23:0] pending_addr;
    logic [63:0] pending_data;

    always @(posedge dut.M_CLK) begin
        if (!btnc && dut.locked) begin
            if (pending) begin
                if (dut.top0.mem_addr !== pending_addr ||
                    (!pending_read && dut.top0.mem_d_to_ram !== pending_data))
                    $fatal(1, "Address/data changed before completion");
                if (dut.top0.mem_transaction_complete) begin
                    if (pending_read && dut.top0.mem_d_from_ram !==
                        (pending_addr == 0 ? WORD0 : WORD1))
                        $fatal(1, "Readback mismatch at addr %0d: %h",
                               pending_addr, dut.top0.mem_d_from_ram);
                    pending = 0;
                    completions = completions + 1;
                end
            end

            if (dut.top0.mem_wstrobe || dut.top0.mem_rstrobe) begin
                if (pending || dut.top0.mem_wstrobe === dut.top0.mem_rstrobe)
                    $fatal(1, "Overlapping or invalid DDR2 request");
                case (requests)
                    0: if (!dut.top0.mem_wstrobe || dut.top0.mem_addr !== 0 ||
                           dut.top0.mem_d_to_ram !== WORD0)
                           $fatal(1, "First microphone word is wrong: %h",
                                  dut.top0.mem_d_to_ram);
                    1: if (!dut.top0.mem_wstrobe || dut.top0.mem_addr !== 2 ||
                           dut.top0.mem_d_to_ram !== WORD1)
                           $fatal(1, "Second microphone word is wrong: %h",
                                  dut.top0.mem_d_to_ram);
                    2: if (!dut.top0.mem_rstrobe || dut.top0.mem_addr !== 0)
                           $fatal(1, "First read request is wrong");
                    3: if (!dut.top0.mem_rstrobe || dut.top0.mem_addr !== 2)
                           $fatal(1, "Second read request is wrong");
                    default: $fatal(1, "Unexpected extra DDR2 request");
                endcase
                pending = 1;
                pending_read = dut.top0.mem_rstrobe;
                pending_addr = dut.top0.mem_addr;
                pending_data = dut.top0.mem_d_to_ram;
                requests = requests + 1;
            end
        end
    end

    integer played_bits = 0;
    always @(negedge dut.M_CLK) begin
        if (dut.playing) begin
            if (played_bits >= 128 || aud_pwm !==
                (played_bits < 64 ? WORD0[63-played_bits] :
                                    WORD1[127-played_bits]))
                $fatal(1, "Playback mismatch at bit %0d: got %b",
                       played_bits, aud_pwm);
            played_bits = played_bits + 1;
        end
    end

    initial begin
        wait (dut.top0.mem_ready === 1'b1);
        if (m_lrsel !== 1'b1 || aud_sd !== 1'b1)
            $fatal(1, "Microphone/audio pins are not configured");

        @(negedge dut.M_CLK) btnu = 1;
        repeat (10) @(negedge dut.M_CLK);
        btnu = 0;
        wait (dut.top0.recorded_words == 1);

        // End recording at the next complete 64-bit word.
        @(negedge dut.M_CLK) btnu = 1;
        repeat (10) @(negedge dut.M_CLK);
        btnu = 0;
        wait (dut.recorded && !dut.recording);
        if (dut.top0.recorded_words != 2 || mic_bits != 128 || dut.overflow)
            $fatal(1, "Recording failed: words=%0d bits=%0d error=%b",
                   dut.top0.recorded_words, mic_bits, dut.overflow);

        @(negedge dut.M_CLK) btnr = 1;
        repeat (10) @(negedge dut.M_CLK);
        btnr = 0;
        wait (dut.recorded && !dut.playing && played_bits == 128);
        #1;
        if (requests != 4 || completions != 4 || led !== 16'h0008)
            $fatal(1, "DDR2/playback failed: req=%0d done=%0d led=%h",
                   requests, completions, led);
        $display("%0t: PASS - microphone bits recorded to DDR2 and played back", $time);
        $finish;
    end

    initial begin
        #(64'd5_000_000_000); // 5 ms, including MIG calibration.
        $fatal(1, "Timeout: req=%0d done=%0d played=%0d",
               requests, completions, played_bits);
    end
endmodule
