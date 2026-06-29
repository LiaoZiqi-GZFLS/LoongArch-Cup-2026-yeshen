## ============================================================================
## fpga_top.xdc  —  board constraints for xc7a200tfbg676-2 (XC7A200T)
## ============================================================================
## fpga_top exposes a REAL physical interface (clk, rstn, seg[7:0], an[7:0]),
## unlike the synthesis-only soc_top. Pin assignments below are PLACEHOLDERS:
## replace every <..._PIN> with the actual package pin of YOUR board.
##
## Valid pins for this device are in soc/constr/xc7a200tfbg676pkg.txt.
## Pins are not needed for synthesis (RTL validation) — only for implementation
## and bitstream generation. Fill them in once the target board is known.
##
## Segment / anode polarity is set in RTL via fpga_top parameters
## (SEG_ACTIVE_LOW / AN_ACTIVE_LOW), default common-anode (active-low).
## seg bit order: seg[0]=a, seg[1]=b, ... seg[6]=g, seg[7]=dp.
## ----------------------------------------------------------------------------

## ---- Clock ----------------------------------------------------------------
## Target 50 MHz (20.000 ns); openLA500 is documented at ~50 MHz on FPGA.
## If your board oscillator is 100 MHz, drive the core via a Clocking Wizard
## (or divider) and retune this period to the actual core clock net.
create_clock -period 20.000 -name clk [get_ports clk]
# set_property -dict { PACKAGE_PIN <CLK_PIN>  IOSTANDARD LVCMOS33 } [get_ports clk]

## ---- Reset (active-low push button) ---------------------------------------
# set_property -dict { PACKAGE_PIN <RST_PIN>  IOSTANDARD LVCMOS33 } [get_ports rstn]

## ---- Seven-segment cathodes {dp,g,f,e,d,c,b,a} ----------------------------
# set_property -dict { PACKAGE_PIN <SEG0_PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[0]}]
# set_property -dict { PACKAGE_PIN <SEG1_PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[1]}]
# set_property -dict { PACKAGE_PIN <SEG2_PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[2]}]
# set_property -dict { PACKAGE_PIN <SEG3_PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[3]}]
# set_property -dict { PACKAGE_PIN <SEG4_PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[4]}]
# set_property -dict { PACKAGE_PIN <SEG5_PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[5]}]
# set_property -dict { PACKAGE_PIN <SEG6_PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[6]}]
# set_property -dict { PACKAGE_PIN <SEG7_PIN> IOSTANDARD LVCMOS33 } [get_ports {seg[7]}]

## ---- Digit-select anodes (one per display) --------------------------------
# set_property -dict { PACKAGE_PIN <AN0_PIN>  IOSTANDARD LVCMOS33 } [get_ports {an[0]}]
# set_property -dict { PACKAGE_PIN <AN1_PIN>  IOSTANDARD LVCMOS33 } [get_ports {an[1]}]
# set_property -dict { PACKAGE_PIN <AN2_PIN>  IOSTANDARD LVCMOS33 } [get_ports {an[2]}]
# set_property -dict { PACKAGE_PIN <AN3_PIN>  IOSTANDARD LVCMOS33 } [get_ports {an[3]}]
# set_property -dict { PACKAGE_PIN <AN4_PIN>  IOSTANDARD LVCMOS33 } [get_ports {an[4]}]
# set_property -dict { PACKAGE_PIN <AN5_PIN>  IOSTANDARD LVCMOS33 } [get_ports {an[5]}]
# set_property -dict { PACKAGE_PIN <AN6_PIN>  IOSTANDARD LVCMOS33 } [get_ports {an[6]}]
# set_property -dict { PACKAGE_PIN <AN7_PIN>  IOSTANDARD LVCMOS33 } [get_ports {an[7]}]
