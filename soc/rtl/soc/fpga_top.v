`timescale 1ns/1ps
// Board-level FPGA top for the Loongson "UDB V1.0" Artix-7 (XC7A200T) edu box.
// Wraps the synthesis SoC (soc_top) and drives the board's physical 8-digit
// seven-segment display, with on-chip clock generation and reset conditioning.
//
// Board interface (pins in soc/constr/fpga_top.xdc, taken from the board's
// master XDC docs/xdc.txt):
//   clk          - 100 MHz board oscillator (AC19)
//   resetn_fpga  - active-low reset button (Y3)
//   num_csn[7:0] - 8 digit-select commons, ACTIVE-LOW ("CSn")
//   num_a_g[6:0] - shared segments a..g, ACTIVE-LOW (common-anode); DP not wired
//
// Clocking: openLA500 is a ~50 MHz core, so a PLLE2_BASE divides the 100 MHz
// board clock down to a 50 MHz CPU clock (matches the reference design's
// cpu_clk). Define SIM_NO_PLL to bypass the PLL in RTL simulation (the UNISIM
// PLLE2_BASE primitive is not available to plain Verilog sims); it is left
// undefined for synthesis so the real PLL is used.
module fpga_top #(
    parameter INIT_FILE      = "",
    parameter SCAN_DIV_BITS  = 16,
    parameter SEG_ACTIVE_LOW = 1'b1,   // common-anode: segment lit when low
    parameter AN_ACTIVE_LOW  = 1'b1    // CSn: digit enabled when low
)(
    input        clk,
    input        resetn_fpga,
    output [7:0] num_csn,
    output [6:0] num_a_g
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
    wire [31:0] cnt_value;        // observable; not driven to pins here

    soc_top #(.INIT_FILE(INIT_FILE)) u_soc(
        .aclk     (cpu_clk),
        .aresetn  (aresetn),
        .seg_disp (seg_disp),
        .cnt_value(cnt_value)
    );

    // ---- physical 7-seg driver ----------------------------------------------
    wire [7:0] seg;               // {dp,g,f,e,d,c,b,a}; dp unused on this board
    seg7_scan #(
        .SCAN_DIV_BITS (SCAN_DIV_BITS),
        .SEG_ACTIVE_LOW(SEG_ACTIVE_LOW),
        .AN_ACTIVE_LOW (AN_ACTIVE_LOW)
    ) u_scan(
        .clk  (cpu_clk),
        .reset(reset),
        .value(seg_disp),
        .seg  (seg),
        .an   (num_csn)
    );
    assign num_a_g = seg[6:0];    // a..g (segment order matches seg7_scan)
endmodule
