# Run with: vivado -mode batch -source setup_vivado.tcl
set project_file C:/DCLAB3_vivado/DCLAB3/DCLAB3.xpr
set tb_file [file normalize [file join [file dirname [info script]] Top_vivado_tb.sv]]
set model_dir [file normalize [file join [file dirname $project_file] DCLAB3.gen sources_1 ip mig_7series_0 mig_7series_0 example_design sim]]
set model_file [file join $model_dir ddr2_model.v]
set params_file [file join $model_dir ddr2_model_parameters.vh]

foreach path [list $project_file $tb_file $model_file $params_file] {
    if {![file exists $path]} { error "Missing required file: $path" }
}

open_project $project_file
foreach path [list $tb_file $model_file $params_file] {
    if {[llength [get_files -quiet $path]] == 0} {
        add_files -fileset sim_1 -norecurse $path
    }
}
set include_dirs [get_property include_dirs [get_filesets sim_1]]
if {[lsearch -exact $include_dirs $model_dir] < 0} {
    lappend include_dirs $model_dir
}
set_property include_dirs $include_dirs [get_filesets sim_1]
set_property top Top_vivado_tb [get_filesets sim_1]
update_compile_order -fileset sim_1
puts "Configured sim_1 with Top_vivado_tb and MIG DDR2 model"
close_project
