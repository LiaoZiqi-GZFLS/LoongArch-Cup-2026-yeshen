set here [file dirname [file normalize [info script]]]
set soc  [file dirname $here]

set wrapper [lindex $argv 0]
set run_ns    [lindex $argv 1]
set workdir   [lindex $argv 2]

set fh [open "$soc/build/generic_files.f" r]
set rtl_sources {}
while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq ""} { continue }
    lappend rtl_sources "$soc/$line"
}
close $fh

lappend rtl_sources $wrapper

set top [file rootname [file tail $wrapper]]
create_project -force "xsim_$top" "$workdir"
add_files -norecurse -fileset sources_1 [concat $rtl_sources $wrapper]
set_property include_dirs [list "$soc/rtl/core"] [get_filesets sources_1]
set_property top $top [get_filesets sources_1]
update_compile_order -fileset sources_1
launch_simulation
run $run_ns ns
close_sim

set log_glob [glob -nocomplain "$workdir/xsim_*.sim/sim_1/behav/xsim/*.log"]
if {[llength $log_glob] > 0} {
    set src_log [lindex $log_glob 0]
    file copy -force $src_log "$workdir/sim.log"
}

puts "XSIM DONE"
