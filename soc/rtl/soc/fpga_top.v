`timescale 1ns/1ps
// Board-level FPGA top for the Loongson "UDB V1.0" Artix-7 (XC7A200T) edu box.
// Wraps the synthesis SoC (soc_top) and drives the board's physical 8-digit
// seven-segment display, LEDs, switches and buttons.
//
// Board interface (pins in soc/constr/fpga_top.xdc, taken from the board's
// master XDC docs/xdc.txt):
//   clk          - 100 MHz board oscillator (AC19)
//   resetn_fpga  - active-low reset button (Y3)
//   num_csn[7:0] - 8 digit-select commons, ACTIVE-LOW ("CSn")
//   num_a_g[6:0] - shared segments a..g, ACTIVE-LOW (common-anode); DP not wired
//   led[15:0]    - monochrome LEDs
//   led_rg0/1[1:0] - red/green LEDs
//   switch_fpga[7:0] - DIP switches (up=1)
//   btn_key_row[3:0], btn_step_fpga[1:0] - button inputs
//
// The ChipLab confreg module inside soc_top already performs 7-seg scan and
// decoding, but its segment output is active-high, so we invert it for this
// active-low/common-anode board.
// Clocking: openLA500 is a ~50 MHz core, so a PLLE2_BASE divides the 100 MHz
// board clock down to a 50 MHz CPU clock. Define SIM_NO_PLL to bypass the PLL
// in RTL simulation.
module fpga_top #(
    parameter INIT_FILE = ""
)(
    input        clk,
    input        resetn_fpga,
    output [7:0] num_csn,
    output [6:0] num_a_g,
    output [15:0] led,
    output [1:0]  led_rg0,
    output [1:0]  led_rg1,
    input  [7:0]  switch_fpga,
    input  [3:0]  btn_key_row,
    input  [1:0]  btn_step_fpga
);
    // ---- 100 MHz -> 50 MHz CPU clock ----------------------------------------
    wire cpu_clk;
    wire locked;
`ifdef SIM_NO_PLL
    assign cpu_clk = clk;
    assign locked  = 1'b1;
`else
    wire clk_fb, cpu_clk_raw;
    PLLE2_BASE #(
        .BANDWIDTH         ("OPTIMIZED"),
        .CLKFBOUT_MULT     (10),          // 100 MHz * 10 = 1000 MHz VCO (in range)
        .CLKFBOUT_PHASE    (0.0),
        .CLKIN1_PERIOD     (10.0),        // 100 MHz input
        .CLKOUT0_DIVIDE    (20),          // 1000 / 20 = 50 MHz
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE     (0.0),
        .DIVCLK_DIVIDE     (1),
        .REF_JITTER1       (0.0),
        .STARTUP_WAIT      ("FALSE")
    ) u_pll (
        .CLKOUT0 (cpu_clk_raw),
        .CLKOUT1 (), .CLKOUT2 (), .CLKOUT3 (), .CLKOUT4 (), .CLKOUT5 (),
        .CLKFBOUT(clk_fb),
        .LOCKED  (locked),
        .CLKIN1  (clk),
        .PWRDWN  (1'b0),
        .RST     (1'b0),
        .CLKFBIN (clk_fb)
    );
    BUFG u_bufg (.I(cpu_clk_raw), .O(cpu_clk));
`endif

    // ---- reset: async assert, sync deassert; held until PLL locks -----------
    wire ext_rst = ~resetn_fpga | ~locked;
    reg [2:0] rst_sync;
    always @(posedge cpu_clk or posedge ext_rst) begin
        if (ext_rst) rst_sync <= 3'b111;
        else         rst_sync <= {rst_sync[1:0], 1'b0};
    end
    wire reset   = rst_sync[2];   // active-high, synchronized to cpu_clk
    wire aresetn = ~reset;        // soc_top expects active-low

    // ---- SoC -----------------------------------------------------------------
    wire [31:0] seg_disp;
    wire [31:0] cnt_value;
    wire [31:0] num_data;
    wire [7:0]  conf_num_csn;
    wire [6:0]  conf_num_a_g;     // active-high from confreg

    soc_top #(.INIT_FILE(INIT_FILE)) u_soc(
        .aclk       (cpu_clk),
        .aresetn    (aresetn),
        .seg_disp   (seg_disp),
        .cnt_value  (cnt_value),
        .led        (led),
        .led_rg0    (led_rg0),
        .led_rg1    (led_rg1),
        .num_csn    (conf_num_csn),
        .num_a_g    (conf_num_a_g),
        .num_data   (num_data),
        .switch     (switch_fpga),
        .btn_key_row(btn_key_row),
        .btn_step   (btn_step_fpga)
    );

    // ---- physical 7-seg driver ----------------------------------------------
    assign num_csn = conf_num_csn;
    assign num_a_g = ~conf_num_a_g;   // invert active-high -> active-low
endmodule
