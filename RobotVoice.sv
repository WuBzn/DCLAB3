// Playback-only voice effect. Keep the recorded DDR2 data in its original
// 3.125 MHz PDM format; convert to PCM only for the effect path.
module RobotVoice #(
    parameter integer DECIMATION = 64,
    // 48,828.125 PCM samples/s / (2 * 244) = 100.06 Hz.
    parameter integer HALF_PERIOD_SAMPLES = 244
)(
    input  logic clk,
    input  logic rst,
    input  logic in_pdm,
    input  logic enable,
    output wire  out_pdm
);
    localparam integer COUNT_WIDTH = $clog2(DECIMATION);
    localparam integer PHASE_WIDTH = $clog2(HALF_PERIOD_SAMPLES);

    // A three-stage, 64:1 CIC decimator. 24-bit arithmetic intentionally
    // wraps modulo 2^24; the three comb stages remove the integrator growth.
    logic signed [23:0] integrator1, integrator2, integrator3;
    logic signed [23:0] comb1, comb2, comb3;
    logic signed [23:0] delay1, delay2, delay3;
    logic [COUNT_WIDTH-1:0] decimation_count;
    logic [PHASE_WIDTH-1:0] phase_count;
    logic carrier_positive;
    logic signed [15:0] pcm_sample, effect_sample;
    logic [15:0] mod_accumulator;
    logic effect_bit;

    wire signed [23:0] pdm_value = in_pdm ? 24'sd1 : -24'sd1;

    function automatic signed [15:0] pcm_from_cic(input signed [23:0] value);
        reg signed [23:0] scaled;
        begin
            // CIC DC gain is 64^3 = 2^18. Shifting by three maps the
            // +/-1 PDM input range to the signed 16-bit PCM range.
            scaled = value >>> 3;
            if (scaled > 24'sd32767)
                pcm_from_cic = 16'sh7fff;
            else if (scaled < -24'sd32768)
                pcm_from_cic = 16'sh8000;
            else
                pcm_from_cic = scaled[15:0];
        end
    endfunction

    wire signed [15:0] next_pcm = pcm_from_cic(comb3);

    // A first-order, 1-bit density modulator runs at the original PDM clock.
    // Signed PCM zero maps to a 50% output density.
    wire [15:0] unsigned_level = effect_sample ^ 16'h8000;
    wire [16:0] mod_sum = {1'b0, mod_accumulator} +
                          {1'b0, unsigned_level};
    assign out_pdm = enable ? effect_bit : in_pdm;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            integrator1 <= 0;
            integrator2 <= 0;
            integrator3 <= 0;
            comb1 <= 0;
            comb2 <= 0;
            comb3 <= 0;
            delay1 <= 0;
            delay2 <= 0;
            delay3 <= 0;
            decimation_count <= 0;
            phase_count <= 0;
            carrier_positive <= 1;
            pcm_sample <= 0;
            effect_sample <= 0;
            mod_accumulator <= 0;
            effect_bit <= 0;
        end else begin
            integrator1 <= integrator1 + pdm_value;
            integrator2 <= integrator2 + integrator1;
            integrator3 <= integrator3 + integrator2;

            mod_accumulator <= mod_sum[15:0];
            effect_bit <= mod_sum[16];

            if (decimation_count == DECIMATION - 1) begin
                decimation_count <= 0;

                // Pipelined comb stages: each stage subtracts its own
                // previous sample. One PCM result is ready every 64 clocks.
                comb1 <= integrator3 - delay1;
                delay1 <= integrator3;
                comb2 <= comb1 - delay2;
                delay2 <= comb1;
                comb3 <= comb2 - delay3;
                delay3 <= comb2;
                pcm_sample <= next_pcm;

                // Square-wave ring modulation: alternate x and -x at
                // approximately 100 Hz without a multiplier.
                if (carrier_positive)
                    effect_sample <= next_pcm;
                else if (next_pcm == 16'sh8000)
                    effect_sample <= 16'sh7fff;
                else
                    effect_sample <= -next_pcm;

                if (phase_count == HALF_PERIOD_SAMPLES - 1) begin
                    phase_count <= 0;
                    carrier_positive <= ~carrier_positive;
                end else begin
                    phase_count <= phase_count + 1'b1;
                end
            end else begin
                decimation_count <= decimation_count + 1'b1;
            end
        end
    end
endmodule
