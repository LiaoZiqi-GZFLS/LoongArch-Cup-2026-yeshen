## ============================================================================
## soc_top.xdc  —  TEMPLATE constraints for xc7a200tfbg676-2 (XC7A200T)
## ============================================================================
## This is a TEMPLATE. Every PACKAGE_PIN below is a PLACEHOLDER and MUST be
## replaced with the actual pins of YOUR board (oscillator, reset button, and —
## once you add a physical 7-seg driver — the segment/anode pins).
##
## Valid package pins for this device are listed in xc7a200tfbg676pkg.txt
## (AMD/Xilinx package pinout). Examples of real bank-12 HR I/O on this part:
##   AE25, AE26, AC22, AC23, AD25, AD26 ...
##
## Pins are NOT required for synthesis — only for implementation / bitstream.
## Run synthesis first to validate the RTL; fill in real pins before impl.
## soc_top ports: aclk, aresetn, seg_disp[31:0], cnt_value[31:0]
## ----------------------------------------------------------------------------

## ---- Clock ----------------------------------------------------------------
## Target 50 MHz (20.000 ns). openLA500 is documented at ~50 MHz on FPGA.
## If your board oscillator is 100 MHz, either retune this period and drive the
## core through a Clocking Wizard / divider, or constrain the actual net.
create_clock -period 20.000 -name aclk [get_ports aclk]

## Clock input pin (REPLACE PACKAGE_PIN with your board's oscillator pin):
# set_property -dict { PACKAGE_PIN <CLK_PIN> IOSTANDARD LVCMOS33 } [get_ports aclk]

## ---- Reset (active-low) ----------------------------------------------------
# set_property -dict { PACKAGE_PIN <RST_PIN> IOSTANDARD LVCMOS33 } [get_ports aresetn]

## ---- Observable outputs ----------------------------------------------------
## NOTE: this synthesis-only top exposes seg_disp / cnt_value as raw 32-bit
## buses, NOT a physical 8-digit 7-seg interface. For a real board, add an
## fpga_top wrapper containing a hex->segment + anode-scan driver and constrain
## THOSE pins instead of these buses.
##
## Illustrative placeholder mapping (REPLACE pins with real LED/header pins):
# set_property -dict { PACKAGE_PIN AE25 IOSTANDARD LVCMOS33 } [get_ports {seg_disp[0]}]
# set_property -dict { PACKAGE_PIN AE26 IOSTANDARD LVCMOS33 } [get_ports {seg_disp[1]}]
# set_property -dict { PACKAGE_PIN AC22 IOSTANDARD LVCMOS33 } [get_ports {seg_disp[2]}]
# set_property -dict { PACKAGE_PIN AC23 IOSTANDARD LVCMOS33 } [get_ports {seg_disp[3]}]

## Until pins are assigned, leaving the wide output buses unconstrained is fine
## for synthesis; they only matter for implementation.
