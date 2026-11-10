# Run with: vivado -mode batch -source sim/setup_robot_voice_vivado.tcl
set project_file C:/DCLAB3_vivado/DCLAB3/DCLAB3.xpr
set source_file [file normalize [file join [file dirname [info script]] .. RobotVoice.sv]]

foreach path [list $project_file $source_file] {
    if {![file exists $path]} { error "Missing required file: $path" }
}

open_project $project_file
if {[llength [get_files -quiet $source_file]] == 0} {
    add_files -fileset sources_1 -norecurse $source_file
}
update_compile_order -fileset sources_1
puts "Added RobotVoice.sv to sources_1"
close_project
