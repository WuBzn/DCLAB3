// Seven-LED relative audio level meter for a 3.125 MHz PDM stream.
// One 64-bit density sample is produced every 20.48 us. The DC tracker
// removes microphone bias; the envelope averages absolute AC magnitude.
module Pdm_Volume_Meter #(
    parameter int DC_SHIFT = 14,  // About 336 ms at 3.125 MHz / 64
    parameter int ENV_SHIFT = 11  // About 42 ms at 3.125 MHz / 64
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       enable,
    input  logic       pdm_bit,
    output logic [6:0] bar,
    output logic signed [31:0] env_level_q
);
    // Keep 16 fractional bits so sub-unit speech levels and decay to zero
    // are both represented accurately at the LED thresholds.
    localparam int ENV_FRAC_BITS = 16;
    localparam int ONE_LEVEL = 1 << ENV_FRAC_BITS;

    logic [5:0] bit_count;
    logic [6:0] ones, ones_next;
    logic signed [31:0] dc_acc;
    logic signed [31:0] env_acc, target_q;
    logic signed [8:0] pcm_now, dc_now;
    logic signed [9:0] ac_now;
    logic [6:0] mag_now;

    // Include the bit sampled on this edge in the completed 64-bit window.
    assign ones_next = ones + {6'b0, pdm_bit};
    assign pcm_now = $signed({1'b0, ones_next}) - 9'sd32;
    assign dc_now = dc_acc >>> DC_SHIFT;
    assign ac_now = pcm_now - dc_now;
    assign mag_now = ac_now[9] ? -ac_now : ac_now;
    assign target_q = $signed({1'b0, mag_now, {ENV_FRAC_BITS{1'b0}}});
    assign env_level_q = env_acc;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_count <= 0;
            ones <= 0;
            dc_acc <= 0;
            env_acc <= 0;
        end else if (!enable) begin
            // Clear the meter when recording/playback is inactive.
            bit_count <= 0;
            ones <= 0;
            dc_acc <= 0;
            env_acc <= 0;
        end else if (bit_count == 6'd63) begin
            bit_count <= 0;
            ones <= 0;
            dc_acc <= dc_acc - (dc_acc >>> DC_SHIFT) + pcm_now;
            env_acc <= env_acc + ((target_q - env_acc) >>> ENV_SHIFT);
        end else begin
            bit_count <= bit_count + 1'b1;
            ones <= ones_next;
        end
    end

    // Relative amplitude thresholds: 0.5, 0.75, 1, 1.5, 2, 3, 4.
    // bar[0] is LED9; bar[6] is LED15.
    assign bar = {
        env_acc >= 4 * ONE_LEVEL,
        env_acc >= 3 * ONE_LEVEL,
        env_acc >= 2 * ONE_LEVEL,
        env_acc >= (3 * ONE_LEVEL) / 2,
        env_acc >= ONE_LEVEL,
        env_acc >= (3 * ONE_LEVEL) / 4,
        env_acc >= ONE_LEVEL / 2
    };
endmodule
