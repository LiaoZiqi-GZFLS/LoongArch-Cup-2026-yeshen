# build.tcl — populate cpu_project with the SoC RTL and optionally run synthesis.
#
# Usage (launch dir does NOT matter — paths are anchored to this script):
#   vivado -mode batch -source soc/scripts/build.tcl              ;# add sources only
#   vivado -mode batch -source soc/scripts/build.tcl -tclargs synth   ;# also synthesize
#
# Design choices baked in here (see soc/NOTICE and CLAUDE.md):
#   * Synthesis top      = fpga_top (board top: soc_top + physical 7-seg driver)
#   * Cache SRAM         = behavioral reg-array models in dcache.v, guarded by
#                          `ifdef SIMU. These are standard BRAM-inference
#                          templates, so SIMU stays DEFINED for synthesis and
#                          Vivado infers Block RAM — no Xilinx SRAM IP needed.
#                          (mycpu.h already has `define SIMU; we do not pass
#                           -verilog_define, to avoid macro-redefine warnings.)
#   * Device             = xc7a200tfbg676-2 (already set in the .xpr)

set here [file dirname [file normalize [info script]]]   ;# .../soc/scripts
set soc  [file dirname $here]                            ;# .../soc
set repo [file dirname $soc]                             ;# repo root
set xpr  "$repo/cpu_project/cpu_project.xpr"

if {![file exists $xpr]} {
    puts "ERROR: project not found: $xpr"
    exit 1
}
open_project $xpr

# ---- idempotent re-run: drop previously added sources/constraints ----
foreach fs {sources_1 constrs_1} {
    set old [get_files -quiet -of_objects [get_filesets $fs]]
    if {[llength $old]} { remove_files -fileset $fs $old }
}

# ---- RTL sources ----
set rtl [concat \
    [glob -nocomplain $soc/rtl/core/*.v] \
    [glob -nocomplain $soc/rtl/soc/*.v] \
    [glob -nocomplain $soc/rtl/periph/*.v]]
add_files -norecurse -fileset sources_1 $rtl

# Verilog headers (`include "mycpu.h" / "csr.h"); Vivado classifies .h as headers.
add_files -norecurse -fileset sources_1 [glob -nocomplain $soc/rtl/core/*.h]

# `include search path + synthesis top.
# update_compile_order first so Vivado's lazy hierarchy/auto-top pass runs now;
# otherwise it fires on the next query and overrides our set_property top.
set_property include_dirs [list "$soc/rtl/core"] [get_filesets sources_1]
update_compile_order -fileset sources_1
set_property top fpga_top [get_filesets sources_1]

# Optional: preinitialize the data BRAM with the demo program for a runnable
# bitstream. Left empty for a clean synthesizability check; uncomment for board.
# set_property generic "INIT_FILE=$soc/sw/demo.mem" [get_filesets sources_1]
# add_files -norecurse -fileset sources_1 $soc/sw/demo.mem

# ---- constraints ----
add_files -norecurse -fileset constrs_1 "$soc/constr/fpga_top.xdc"

puts "==== sources_1 ===="
foreach f [get_files -of_objects [get_filesets sources_1]] { puts "  $f" }
puts "top        = [get_property top [get_filesets sources_1]]"
puts "include    = [get_property include_dirs [get_filesets sources_1]]"

# ---- optional synthesis ----
if {[lsearch $argv "synth"] >= 0} {
    reset_run synth_1
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    set prog [get_property PROGRESS [get_runs synth_1]]
    set stat [get_property STATUS   [get_runs synth_1]]
    puts "==== synth_1: progress=$prog status=$stat ===="
    if {$prog != "100%"} {
        puts "ERROR: synthesis did not complete"
        exit 1
    }
    open_run synth_1 -name synth_1
    puts "==== utilization ===="
    report_utilization
    puts "==== timing summary ===="
    report_timing_summary -max_paths 1 -delay_type max
    puts "SYNTH OK"
}
puts "BUILD DONE"
