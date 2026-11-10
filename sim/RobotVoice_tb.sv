`timescale 1ns/1ps

module RobotVoice_tb;
    logic clk = 0, rst = 1, in_pdm = 0, enable = 0;
    wire out_pdm;
    integer i, positive_seen, negative_seen, ones;

    always #5 clk = ~clk;

    // Short carrier period makes both ring-modulator polarities observable.
    RobotVoice #(.HALF_PERIOD_SAMPLES(8)) dut (
        .clk(clk), .rst(rst), .in_pdm(in_pdm),
        .enable(enable), .out_pdm(out_pdm)
    );

    task automatic check_density(input bit expect_high);
        integer k, high_bits;
        begin
            high_bits = 0;
            // Skip the first modulator cycle after a PCM update.
            @(negedge clk);
            for (k = 0; k < 32; k = k + 1) begin
                @(negedge clk);
                high_bits = high_bits + out_pdm;
            end
            if (expect_high && high_bits < 30)
                $fatal(1, "Positive PCM density too low: %0d/32", high_bits);
            if (!expect_high && high_bits > 2)
                $fatal(1, "Negative PCM density too high: %0d/32", high_bits);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 0;

        // Bypass must preserve every original bit, including rapid changes.
        for (i = 0; i < 256; i = i + 1) begin
            @(negedge clk);
            in_pdm = ((i * 7 + i / 3) % 5) < 2;
            #1;
            if (out_pdm !== in_pdm)
                $fatal(1, "Bypass changed bit %0d", i);
        end

        // All-one PDM is positive full-scale PCM. After CIC settling,
        // the carrier must alternate the PCM sign without changing rate.
        enable = 1;
        in_pdm = 1;
        repeat (640) @(negedge clk);
        positive_seen = 0;
        negative_seen = 0;
        for (i = 0; i < 24 * 64; i = i + 1) begin
            @(negedge clk);
            if (dut.decimation_count == 0) begin
                if (dut.pcm_sample !== 16'sh7fff)
                    $fatal(1, "CIC positive DC = %0d", dut.pcm_sample);
                if (dut.effect_sample == 16'sh7fff)
                    positive_seen = positive_seen + 1;
                else if (dut.effect_sample == -16'sd32767)
                    negative_seen = negative_seen + 1;
                else
                    $fatal(1, "Unexpected ring-modulated sample %0d",
                           dut.effect_sample);
            end
        end
        if (positive_seen < 4 || negative_seen < 4)
            $fatal(1, "Carrier did not alternate: +%0d -%0d",
                   positive_seen, negative_seen);

        wait (dut.decimation_count == 0 && dut.effect_sample == 16'sh7fff);
        check_density(1);
        wait (dut.decimation_count == 0 && dut.effect_sample == -16'sd32767);
        check_density(0);

        // The opposite DC level checks the full-scale negative path.
        in_pdm = 0;
        repeat (640) @(negedge clk);
        if (dut.pcm_sample !== 16'sh8000)
            $fatal(1, "CIC negative DC = %0d", dut.pcm_sample);

        // A balanced PDM stream represents silence; its regenerated PDM
        // should have approximately half of its bits high.
        for (i = 0; i < 768; i = i + 1) begin
            @(negedge clk);
            in_pdm = i[0];
        end
        if (dut.pcm_sample < -16'sd1 || dut.pcm_sample > 16'sd1)
            $fatal(1, "Balanced PDM did not settle to zero: %0d",
                   dut.pcm_sample);
        ones = 0;
        for (i = 0; i < 128; i = i + 1) begin
            @(negedge clk);
            in_pdm = i[0];
            ones = ones + out_pdm;
        end
        if (ones < 60 || ones > 68)
            $fatal(1, "Silence density = %0d/128", ones);

        enable = 0;
        #1;
        if (out_pdm !== in_pdm)
            $fatal(1, "Bypass did not recover after effect");

        $display("PASS: robot voice bypass, CIC, modulation, and PDM output");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Robot voice test timed out");
    end
endmodule
