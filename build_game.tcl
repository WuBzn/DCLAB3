# Add the game RTL to the existing Lab3 Vivado project and build a game bitstream.
# Run: vivado.bat -mode batch -source build_game.tcl \
#      -log C:/DCLAB3_vivado/DCLAB3/game_build.log \
#      -journal C:/DCLAB3_vivado/DCLAB3/game_build.jou
set project_file C:/DCLAB3_vivado/DCLAB3/DCLAB3.xpr
set source_dir [file dirname [file normalize [info script]]]
set game_files [list Game_Level_Config.sv Game_Controller.sv Game_SevenSegment.sv Game_VGA.sv]
set timing_file [file normalize [file join $source_dir game_timing.xdc]]
set bit_file [file join [file dirname $project_file] DCLAB3.runs impl_1 NEXYS_A7.bit]
set output_file [file join [file dirname $project_file] NEXYS_A7_game.bit]

if {![file exists $project_file]} { error "Missing Vivado project: $project_file" }
foreach name $game_files {
    set path [file join $source_dir $name]
    if {![file exists $path]} { error "Missing game source: $path" }
}
if {![file exists $timing_file]} { error "Missing game constraints: $timing_file" }
if {[file exists $bit_file]} {
    set backup [file join [file dirname $project_file] \
        "NEXYS_A7_before_game_[clock format [clock seconds] -format %Y%m%d_%H%M%S].bit"]
    file copy $bit_file $backup
    puts "Previous bitstream saved: $backup"
}

open_project $project_file
foreach name $game_files {
    set path [file normalize [file join $source_dir $name]]
    if {[llength [get_files -quiet $path]] == 0} {
        add_files -fileset sources_1 -norecurse $path
    }
}
# VGA multicycle constraint; cell names are final only after synthesis.
if {[llength [get_files -quiet $timing_file]] == 0} {
    add_files -fileset constrs_1 -norecurse $timing_file
}
set_property used_in_synthesis false [get_files $timing_file]
set_property top NEXYS_A7 [get_filesets sources_1]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {[string first "Complete!" $synth_status] < 0} {
    error "Synthesis failed: $synth_status"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {[string first "Complete!" $impl_status] < 0} {
    error "Implementation failed: $impl_status"
}

open_run impl_1
# The game runs on the board clock; make sure it is really being timed.
if {[llength [get_clocks -quiet -of_objects [get_pins {game_vga0/rgb_q_reg[0]/C}]]] == 0} {
    error "Game logic is not reached by a timing clock"
}
set game_path [lindex [get_timing_paths -quiet -delay_type max -max_paths 1 \
    -to [get_clocks game_clk]] 0]
if {$game_path ne ""} {
    puts "Game clock worst setup slack: [get_property SLACK $game_path] ns"
}
set setup_path [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
set hold_path [lindex [get_timing_paths -delay_type min -max_paths 1] 0]
if {$setup_path eq "" || $hold_path eq ""} {
    error "Cannot determine routed timing slack"
}
set setup_slack [get_property SLACK $setup_path]
set hold_slack [get_property SLACK $hold_path]
puts "Game routed timing: setup $setup_slack ns; hold $hold_slack ns"
if {$setup_slack < 0 || $hold_slack < 0} {
    error "Game has a routed timing violation"
}
file copy -force $bit_file $output_file
puts "Game bitstream ready: $output_file"
close_project
