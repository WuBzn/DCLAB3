module NEXYS_A7 #(
    parameter int DEBOUNCE_CYCLES = 31_250,
    parameter int MAX_WORDS = 781_250
)(
    //Clock signal
    input CLK100MHZ,
    //Switches
    input [15:0]SW,
    //LEDs
    output [15:0]LED,
    //RGB LEDs
    output LED16_B,
    output LED16_G,
    output LED16_R,
    output LED17_B,
    output LED17_G,
    output LED17_R,
    //7 segment display
    output CA,
    output CB,
    output CC,
    output CD,
    output CE,
    output CF,
    output CG,
    output DP,
    output [7:0]AN,
    //CPU Reset Button
    input CPU_RESETN,
    //Buttons
    input BTNC,
    input BTNU,
    input BTNL,
    input BTNR,
    input BTND,
    //Pmod Headers
    inout [10:0]JA,
    inout [10:0]JB,
    inout [10:0]JC,
    inout [10:0]JD,
    inout [4:0]XA_N,
    inout [4:0]XA_P,
    //VGA Connector
    output [3:0]VGA_R,
    output [3:0]VGA_G,
    output [3:0]VGA_B,
    output VGA_HS,
    output VGA_VS,
    //Micro SD Connector
    output SD_RESET,
    input SD_CD,
    inout SD_SCK,
    inout SD_CMD,
    inout [3:0]SD_DAT,
    //Accelerometer
    input ACL_MISO,
    output ACL_MOSI,
    output ACL_SCLK,
    output ACL_CSN,
    input [2:0]ACL_INT,
    //Temperature Sensor
    output TMP_SCL,
    inout TMP_SDA,
    input TMP_INT,
    input TMP_CT,
    //Omnidirectional Microphone
    output M_CLK,
    input M_DATA,
    output M_LRSEL,
    //PWM Audio Amplifier
    output AUD_PWM,
    output AUD_SD,
    //USB-RS232 Interface
    input UART_TXD_IN,
    output UART_RXD_OUT,
    output UART_CTS,
    input UART_RTS,
    //USB HID (PS/2)
    inout PS2_CLK,
    inout PS2_DATA,
    //SMSC Ethernet PHY
    output ETH_MDC,
    inout ETH_MDIO,
    output ETH_RSTN,
    inout ETH_CRSDV,
    inout ETH_RXERR,
    inout [1:0]ETH_RXD,
    output ETH_TXEN,
    output [1:0]ETH_TXD,
    inout ETH_REFCLK,
    inout ETH_INTN,
    //Quad SPI Flash
    inout [3:0]QSPI_DQ,
    output QSPI_CSN,
    //ddr2 sdram
    output [12:0]ddr2_addr,
    output [2:0]ddr2_ba,
    output ddr2_ras_n,
    output ddr2_cas_n,
    output ddr2_we_n,
    output ddr2_ck_p,
    output ddr2_ck_n,
    output ddr2_cke,
    output ddr2_cs_n,
    output [1:0]ddr2_dm,
    output ddr2_odt,
    inout [15:0]ddr2_dq,
    inout [1:0]ddr2_dqs_p,
    inout [1:0]ddr2_dqs_n
    );

    logic BTNU_down,BTNR_down,BTND_down,locked,CLK200MHZ;
    logic audio_bit, recording, playing, paused, recorded, overflow;
    logic reverse_select, reverse_mode;
    logic [3:0] speed_select;
    logic [4:0] display_seconds;
    logic [6:0] volume_bar;
    logic signed [31:0] volume_env_q;
    logic game_mode_audio, game_mode_video;
    logic [7:0] game_direction;
    logic [6:0] game_volume_bar, game_volume_bar_audio;
    logic game_start, game_left, game_right, game_reset_press;
    logic [2:0] game_state;
    logic [1:0] game_level;
    logic [2:0] game_selected;
    logic [5:0] game_seconds, game_time_limit;
    logic [7:0] game_locked;
    logic [79:0] game_positions;
    logic [79:0] game_targets, game_initial_positions;
    logic [15:0] game_mid_codes, game_end_codes;
    logic [9:0] game_source_y, game_goal_y;
    logic [7:0] game_initial_locked;
    logic [9:0] game_ball_x;
    logic rec_CA,rec_CB,rec_CC,rec_CD,rec_CE,rec_CF,rec_CG,rec_DP;
    logic game_CA,game_CB,game_CC,game_CD,game_CE,game_CF,game_CG,game_DP;
    logic [7:0] rec_AN,game_AN;
    
    clk_wiz_0 clk_wiz(
    .reset(BTNC),
    .clk_in1(CLK100MHZ),
    .clk_out1(CLK200MHZ),
    .clk_out5(M_CLK),
    .locked(locked)
    );

    // The microphone updates data on M_CLK's falling edge; Top samples rising.
    assign M_LRSEL = 1'b1;
    // The board has the pull-up required by its open-drain audio input.
    assign AUD_PWM = audio_bit ? 1'bz : 1'b0;
    assign AUD_SD = 1'b1;
    ff_sync #(.WIDTH(4)) speed_sync(
        .clk(M_CLK), .rst_p(BTNC || !locked),
        .in_async(SW[3:0]), .out(speed_select)
    );
    ff_sync direction_sync(
        .clk(M_CLK), .rst_p(BTNC || !locked),
        .in_async(SW[4]), .out(reverse_select)
    );
    ff_sync game_mode_audio_sync(
        .clk(M_CLK), .rst_p(BTNC || !locked),
        .in_async(SW[15]), .out(game_mode_audio)
    );
    ff_sync game_mode_video_sync(
        .clk(CLK100MHZ), .rst_p(BTNC || !locked),
        .in_async(SW[15]), .out(game_mode_video)
    );
    ff_sync #(.WIDTH(8)) game_direction_sync(
        .clk(CLK100MHZ), .rst_p(BTNC || !locked),
        .in_async({SW[7], SW[8], SW[9], SW[10],
                   SW[11], SW[12], SW[13], SW[14]}),
        .out(game_direction)
    );
    
    
    Top #(.MAX_WORDS(MAX_WORDS)) top0(
    .clk(M_CLK),
    .locked(locked),
    .rst(BTNC),
    .data_in(M_DATA),
    .data_out(audio_bit),
    .record_press(BTNU_down && !game_mode_audio),
    .play_pause_press(BTNR_down && !game_mode_audio),
    .stop_press(BTND_down || game_mode_audio),
    .speed_select(speed_select),
    .reverse_select(reverse_select),
    .recording(recording),
    .playing(playing),
    .paused(paused),
    .recorded(recorded),
    .reverse_mode(reverse_mode),
    .overflow(overflow),
    .display_seconds(display_seconds),

    //ddr2 Interface
    .ddr2_addr(ddr2_addr),
    .ddr2_ba(ddr2_ba),
    .ddr2_cas_n(ddr2_cas_n),
    .ddr2_ck_n(ddr2_ck_n),
    .ddr2_ck_p(ddr2_ck_p),
    .ddr2_cke(ddr2_cke),
    .ddr2_ras_n(ddr2_ras_n),
    .ddr2_we_n(ddr2_we_n),
    .ddr2_dq(ddr2_dq),
    .ddr2_dqs_n(ddr2_dqs_n),
    .ddr2_dqs_p(ddr2_dqs_p),
    .ddr2_cs_n(ddr2_cs_n),
    .ddr2_dm(ddr2_dm),
    .ddr2_odt(ddr2_odt),
    .clk_mem(CLK200MHZ)
    );

    // The game always measures the live microphone. Recorder mode preserves
    // its original input/output meter behavior.
    Pdm_Volume_Meter volume_meter0 (
        .clk(M_CLK),
        .rst(BTNC || !locked),
        .enable(game_mode_audio || recording || playing),
        .pdm_bit(game_mode_audio || recording ? M_DATA : audio_bit),
        .bar(volume_bar),
        .env_level_q(volume_env_q)
    );
    // Speech-friendly game thresholds: half the recorder meter thresholds.
    assign game_volume_bar_audio = {
        volume_env_q >= 32'sd131072,
        volume_env_q >= 32'sd98304,
        volume_env_q >= 32'sd65536,
        volume_env_q >= 32'sd49152,
        volume_env_q >= 32'sd32768,
        volume_env_q >= 32'sd24576,
        volume_env_q >= 32'sd16384
    };
    ff_sync #(.WIDTH(7)) game_volume_sync(
        .clk(CLK100MHZ), .rst_p(BTNC || !locked),
        .in_async(game_volume_bar_audio), .out(game_volume_bar)
    );

    // Game buttons are debounced in the 100 MHz video/game domain.
    Debounce #(.CNT_N(DEBOUNCE_CYCLES * 32)) game_start_button(
        .i_in(BTNU), .i_clk(CLK100MHZ), .i_rst(BTNC), .o_pos(game_start)
    );
    Debounce #(.CNT_N(DEBOUNCE_CYCLES * 32)) game_left_button(
        .i_in(BTNL), .i_clk(CLK100MHZ), .i_rst(BTNC), .o_pos(game_left)
    );
    Debounce #(.CNT_N(DEBOUNCE_CYCLES * 32)) game_right_button(
        .i_in(BTNR), .i_clk(CLK100MHZ), .i_rst(BTNC), .o_pos(game_right)
    );
    Debounce #(.CNT_N(DEBOUNCE_CYCLES * 32)) game_reset_button(
        .i_in(BTND), .i_clk(CLK100MHZ), .i_rst(BTNC), .o_pos(game_reset_press)
    );
    Game_Level_Config game_config0 (
        .level(game_level), .time_limit(game_time_limit),
        .source_y(game_source_y), .goal_y(game_goal_y),
        .target_positions(game_targets),
        .initial_positions(game_initial_positions),
        .initial_locked(game_initial_locked),
        .mid_codes(game_mid_codes), .end_codes(game_end_codes)
    );
    Game_Controller game0 (
        .clk(CLK100MHZ), .rst(BTNC || !locked), .enable(game_mode_video),
        .start_press(game_start), .left_press(game_left),
        .right_press(game_right), .reset_press(game_reset_press),
        .pipe_direction(game_direction), .volume_bar(game_volume_bar),
        .time_limit(game_time_limit),
        .target_positions(game_targets),
        .initial_positions(game_initial_positions),
        .initial_locked(game_initial_locked),
        .state(game_state), .level(game_level), .selected(game_selected),
        .seconds_left(game_seconds), .pipe_locked(game_locked),
        .pipe_positions(game_positions), .ball_x(game_ball_x)
    );
    Game_VGA game_vga0 (
        .clk(CLK100MHZ), .rst(BTNC || !locked), .enable(game_mode_video),
        .state(game_state), .level(game_level), .selected(game_selected),
        .seconds_left(game_seconds), .pipe_locked(game_locked),
        .pipe_positions(game_positions), .ball_x(game_ball_x),
        .volume_bar(game_volume_bar), .pipe_direction(game_direction),
        .source_y(game_source_y), .goal_y(game_goal_y),
        .target_positions(game_targets),
        .mid_codes(game_mid_codes), .end_codes(game_end_codes),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS)
    );

    ila_0 ila_volume0 (
        .clk(M_CLK),
        .probe0(volume_env_q)
    );

    // Game: LED9-15 volume, LED8 mode, LED0-7 locked pipes.
    // Recorder: original speed and status indicators.
    assign LED = game_mode_video ?
                 {game_volume_bar, 1'b1, game_locked} :
                 {volume_bar, speed_select,
                  overflow, recorded, paused, playing, recording};
    assign LED16_R = game_mode_video ? (game_state == 3'd6) : reverse_mode;
    assign LED16_G = game_mode_video && (game_state == 3'd5 || game_state == 3'd7);
    assign LED16_B = game_mode_video && game_state == 3'd4;

    Seven_Segment_Display seven0(
        .i_clk(M_CLK),
        .i_rst(BTNC || !locked),
        .i_recording(recording),
        .i_playing(playing),
        .i_paused(paused),
        .i_recorded(recorded),
        .i_overflow(overflow),
        .i_seconds(display_seconds),
        .i_speed(speed_select),
        .CA(rec_CA),
        .CB(rec_CB),
        .CC(rec_CC),
        .CD(rec_CD),
        .CE(rec_CE),
        .CF(rec_CF),
        .CG(rec_CG),
        .DP(rec_DP),
        .o_an(rec_AN)
    );
    Game_SevenSegment game_seven0 (
        .clk(CLK100MHZ), .rst(BTNC || !locked),
        .level(game_level), .seconds_left(game_seconds),
        .selected(game_selected),
        .CA(game_CA), .CB(game_CB), .CC(game_CC), .CD(game_CD),
        .CE(game_CE), .CF(game_CF), .CG(game_CG), .DP(game_DP),
        .AN(game_AN)
    );
    assign {CA,CB,CC,CD,CE,CF,CG,DP,AN} = game_mode_video ?
           {game_CA,game_CB,game_CC,game_CD,game_CE,game_CF,game_CG,game_DP,game_AN} :
           {rec_CA,rec_CB,rec_CC,rec_CD,rec_CE,rec_CF,rec_CG,rec_DP,rec_AN};
    Debounce #(.CNT_N(DEBOUNCE_CYCLES)) deb0(
        .i_in(BTNU),
        .i_clk(M_CLK),
        .i_rst(BTNC),
        .o_pos(BTNU_down)
    );
    
    Debounce #(.CNT_N(DEBOUNCE_CYCLES)) deb1(
        .i_in(BTNR),
        .i_clk(M_CLK),
        .i_rst(BTNC),
        .o_pos(BTNR_down)
    );
    
    Debounce #(.CNT_N(DEBOUNCE_CYCLES)) deb2(
        .i_in(BTND),
        .i_clk(M_CLK),
        .i_rst(BTNC),
        .o_pos(BTND_down)
    );

endmodule


