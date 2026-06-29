## ============================================================================
## fpga_top.xdc  —  board constraints for the Loongson "UDB V1.0" edu box
##                  (Xilinx Artix-7 XC7A200T, package fbg676, speed -2)
## ============================================================================
## Pin assignments are taken verbatim from the board's master XDC (docs/xdc.txt).
## Only the ports fpga_top actually exposes are constrained here:
##   clk          100 MHz board oscillator
##   resetn_fpga  active-low reset push button
##   num_csn[7:0] 8 digit-select commons (active-low "CSn")
##   num_a_g[6:0] shared segments a..g (active-low / common-anode)
## All other board peripherals (led, switch, uart, ...) are intentionally omitted.
## Segment/anode polarity is set in RTL via fpga_top params SEG_ACTIVE_LOW /
## AN_ACTIVE_LOW (default common-anode, active-low).
## ----------------------------------------------------------------------------

## ---- Clock: 100 MHz oscillator on AC19 ------------------------------------
set_property PACKAGE_PIN AC19 [get_ports clk]
set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets clk_IBUF]
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]
## The 50 MHz cpu_clk is derived by the PLLE2_BASE inside fpga_top; Vivado
## auto-generates the corresponding generated clock from CLKOUT0, so no explicit
## create_generated_clock is needed here.

## ---- Reset (active-low push button) ---------------------------------------
set_property PACKAGE_PIN Y3 [get_ports resetn_fpga]

## ---- Seven-segment digit-select commons num_csn[7:0] (active-low) ----------
set_property PACKAGE_PIN D3  [get_ports {num_csn[7]}]
set_property PACKAGE_PIN D25 [get_ports {num_csn[6]}]
set_property PACKAGE_PIN D26 [get_ports {num_csn[5]}]
set_property PACKAGE_PIN E25 [get_ports {num_csn[4]}]
set_property PACKAGE_PIN E26 [get_ports {num_csn[3]}]
set_property PACKAGE_PIN G25 [get_ports {num_csn[2]}]
set_property PACKAGE_PIN G26 [get_ports {num_csn[1]}]
set_property PACKAGE_PIN H26 [get_ports {num_csn[0]}]

## ---- Seven-segment shared segments num_a_g[6:0] = a..g (active-low) --------
set_property PACKAGE_PIN C3 [get_ports {num_a_g[0]}]
set_property PACKAGE_PIN E6 [get_ports {num_a_g[1]}]
set_property PACKAGE_PIN B2 [get_ports {num_a_g[2]}]
set_property PACKAGE_PIN B4 [get_ports {num_a_g[3]}]
set_property PACKAGE_PIN E5 [get_ports {num_a_g[4]}]
set_property PACKAGE_PIN D4 [get_ports {num_a_g[5]}]
set_property PACKAGE_PIN A2 [get_ports {num_a_g[6]}]
## DP (C4) is not wired in fpga_top.

## ---- I/O standards --------------------------------------------------------
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports resetn_fpga]
set_property IOSTANDARD LVCMOS33 [get_ports {num_csn[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {num_a_g[*]}]

## ---- Config bank voltage (silences DRC CFGBVS-1; board config bank is 3.3V) -
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
