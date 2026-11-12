# Build the current RTL in the existing Vivado project.
# Run from this directory with: vivado -mode batch -source build_volume_led.tcl
set project_file C:/DCLAB3_vivado/DCLAB3/DCLAB3.xpr
set meter_file [file normalize [file join [file dirname [info script]] Pdm_Volume_Meter.sv]]

foreach path [list $project_file $meter_file] {
    if {![file exists $path]} { error "Missing required file: $path" }
}

open_project $project_file
if {[llength [get_files -quiet $meter_file]] == 0} {
    add_files -fileset sources_1 -norecurse $meter_file
}
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

puts "Bitstream ready: [file join [file dirname $project_file] DCLAB3.runs impl_1 NEXYS_A7.bit]"
close_project
