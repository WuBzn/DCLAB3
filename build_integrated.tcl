# Build the integrated RTL in the existing Vivado project.
# Run with: vivado -mode batch -source build_integrated.tcl
set project_file C:/DCLAB3_vivado/DCLAB3/DCLAB3.xpr
set meter_file [file normalize [file join [file dirname [info script]] Pdm_Volume_Meter.sv]]
set cdc_file [file normalize [file join [file dirname [info script]] cdc_timing.xdc]]
set bit_file [file join [file dirname $project_file] DCLAB3.runs impl_1 NEXYS_A7.bit]
set output_file [file join [file dirname $project_file] NEXYS_A7_integrated.bit]

foreach path [list $project_file $meter_file $cdc_file] {
    if {![file exists $path]} { error "Missing required file: $path" }
}

# Keep the currently programmed design available when rebuilding this project.
if {[file exists $bit_file]} {
    set backup [file join [file dirname $project_file] \
        "NEXYS_A7_before_integrated_[clock format [clock seconds] -format %Y%m%d_%H%M%S].bit"]
    file copy $bit_file $backup
    puts "Previous bitstream saved: $backup"
}

open_project $project_file
if {[llength [get_files -quiet $meter_file]] == 0} {
    add_files -fileset sources_1 -norecurse $meter_file
}
if {[llength [get_files -quiet $cdc_file]] == 0} {
    add_files -fileset constrs_1 -norecurse $cdc_file
}
set_property used_in_synthesis false [get_files $cdc_file]
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
set setup_path [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
set hold_path [lindex [get_timing_paths -delay_type min -max_paths 1] 0]
if {$setup_path eq "" || $hold_path eq ""} {
    error "Cannot determine routed timing slack"
}
set setup_slack [get_property SLACK $setup_path]
set hold_slack [get_property SLACK $hold_path]
puts "Routed timing: setup slack $setup_slack ns; hold slack $hold_slack ns"
if {$setup_slack < 0 || $hold_slack < 0} {
    error "Routed design has a timing violation"
}

file copy -force $bit_file $output_file
puts "Integrated bitstream ready: $output_file"
close_project
