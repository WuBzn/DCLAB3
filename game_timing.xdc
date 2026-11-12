# The game logic runs directly on the 100 MHz board clock. The clock wizard
# IP defines its own clock on its internal clk_in1 pin, which does not reach
# this fabric logic, so define the board clock on the port as well.
create_clock -period 10.000 -name game_clk [get_ports CLK100MHZ]

# The 100 MHz game domain exchanges data with the clock-wizard clocks
# (microphone/audio and DDR2) only through ff_sync two-flop synchronizers.
set_clock_groups -asynchronous \
    -group [get_clocks game_clk] \
    -group [get_clocks -include_generated_clocks clk_wiz/inst/clk_in1]

# Game_VGA computes each pixel colour combinationally from the pixel counters,
# the per-frame snapshot and the animation counter. All of these registers
# change only on the 25 MHz pixel enable (every fourth 100 MHz edge), and
# rgb_q samples the colour on the next enable, so the path has four cycles.
# pixel_phase and rgb_q itself are not listed and keep single-cycle checks.
set vga_sources [get_cells -hierarchical -filter {NAME =~ game_vga0/h_reg* || NAME =~ game_vga0/v_reg* || NAME =~ game_vga0/*_frame_reg* || NAME =~ game_vga0/anim_reg*}]
set vga_colour [get_pins -hierarchical -filter {NAME =~ game_vga0/rgb_q_reg*/D}]
set_multicycle_path 4 -setup -from $vga_sources -to $vga_colour
set_multicycle_path 3 -hold -from $vga_sources -to $vga_colour
