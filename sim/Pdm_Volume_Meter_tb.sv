`timescale 1ns/1ps

module Pdm_Volume_Meter_tb;
    logic clk = 0;
    logic rst = 1;
    logic enable = 0;
    logic pdm_bit = 0;
    wire [6:0] bar;

    always #5 clk = ~clk;

    // Shorter time constants keep the behavior test fast. The production
    // instance uses the module defaults (DC_SHIFT=14, ENV_SHIFT=11).
    Pdm_Volume_Meter #(.DC_SHIFT(8), .ENV_SHIFT(5)) dut (
        .clk(clk), .rst(rst), .enable(enable),
        .pdm_bit(pdm_bit), .bar(bar)
    );

    // Distribute exactly count ones through one 64-bit PDM window.
    task automatic send_block(input integer count);
        integer i;
        begin
            for (i = 0; i < 64; i = i + 1) begin
                @(negedge clk);
                pdm_bit = (((i + 1) * count) / 64 != (i * count) / 64);
            end
        end
    endtask

    task automatic check_bar(input [6:0] expected, input string label_text);
        begin
            @(posedge clk);
            #1;
            if (bar !== expected)
                $fatal(1, "%s: bar=%b env_acc=%0d expected=%b",
                       label_text, bar, dut.env_acc, expected);
        end
    endtask

    integer i;
    initial begin
        repeat (2) @(negedge clk);
        rst = 0;
        enable = 1;

        // 50% density is silence and must not light the meter.
        for (i = 0; i < 100; i = i + 1) send_block(32);
        check_bar(7'b0000000, "silence");

        // Mean magnitude 2/3 is between the 0.5 and 0.75 thresholds.
        for (i = 0; i < 200; i = i + 1) begin
            send_block(33);
            send_block(31);
            send_block(32);
        end
        check_bar(7'b0000001, "fractional AC level");

        // Mean magnitude 2.5 crosses the first five thresholds.
        for (i = 0; i < 250; i = i + 1) begin
            send_block(35);
            send_block(30);
        end
        check_bar(7'b0011111, "medium AC level");

        // Amplitude 16 passes all seven thresholds.
        for (i = 0; i < 250; i = i + 1) begin
            send_block(48);
            send_block(16);
        end
        check_bar(7'b1111111, "high AC level");

        // A quiet input must eventually extinguish every LED. The old
        // integer-feedback envelope could stick below one unit forever.
        for (i = 0; i < 300; i = i + 1) send_block(32);
        check_bar(7'b0000000, "decay to silence");

        enable = 0;
        check_bar(7'b0000000, "inactive meter");

        enable = 1;
        // A fixed 62.5% density is a DC offset, not an audio waveform.
        for (i = 0; i < 1600; i = i + 1) send_block(40);
        check_bar(7'b0000000, "DC rejection");

        $display("PASS: fractional threshold, two levels, silence decay, inactive clear, and DC rejection");
        $finish;
    end

    initial begin
        #5000000;
        $fatal(1, "Volume meter test timed out");
    end
endmodule
