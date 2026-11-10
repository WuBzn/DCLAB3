# Run after setup_robot_voice_vivado.tcl to produce an updated bitstream.
set project_file C:/DCLAB3_vivado/DCLAB3/DCLAB3.xpr
if {![file exists $project_file]} { error "Missing project: $project_file" }

open_project $project_file
# New external RTL files do not always invalidate an existing completed run.
reset_runs impl_1
reset_runs synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set run_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $run_status"
if {$run_status ne "write_bitstream Complete!"} {
    error "Bitstream build failed: $run_status"
}
close_project
