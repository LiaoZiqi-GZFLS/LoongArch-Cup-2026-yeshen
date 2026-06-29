`timescale 1ns/1ps
// Board-level FPGA top: wraps the synthesis SoC (soc_top) and adds a physical
// 8-digit seven-segment driver plus reset synchronization, so the design can be
// constrained to real package pins and put on a board.
//
// Ports map to physical I/O (assign pins in soc/constr/fpga_top.xdc):
//   clk    - board oscillator
//   rstn   - active-low reset (e.g. a push button)
//   seg    - seven-segment cathodes/anodes {dp,g,f,e,d,c,b,a}
//   an     - 8 digit-select lines
//
// The SoC's MMIO seg7 register (soc_top.seg_disp) is the value shown; the cycle
// counter (soc_top.cnt_value) is left observable but not displayed here.
// Segment/anode active levels are forwarded to seg7_scan parameters; flip
// SEG_ACTIVE_LOW / AN_ACTIVE_LOW below to match your panel.
module fpga_top #(
    parameter INIT_FILE      = "",
    parameter SCAN_DIV_BITS  = 16,
    parameter SEG_ACTIVE_LOW = 1'b1,
    parameter AN_ACTIVE_LOW  = 1'b1
)(
    input        clk,
    input        rstn,
    output [7:0] seg,
    output [7:0] an
);
    // Synchronize the asynchronous reset button into the clk domain.
    reg [1:0] rst_sync;
    always @(posedge clk) rst_sync <= {rst_sync[0], ~rstn};
    wire reset   = rst_sync[1];   // active-high, synchronized
    wire aresetn = ~reset;        // soc_top expects active-low

    wire [31:0] seg_disp;
    wire [31:0] cnt_value;        // observable; not driven to pins here

    soc_top #(.INIT_FILE(INIT_FILE)) u_soc(
        .aclk     (clk),
        .aresetn  (aresetn),
        .seg_disp (seg_disp),
        .cnt_value(cnt_value)
    );

    seg7_scan #(
        .SCAN_DIV_BITS (SCAN_DIV_BITS),
        .SEG_ACTIVE_LOW(SEG_ACTIVE_LOW),
        .AN_ACTIVE_LOW (AN_ACTIVE_LOW)
    ) u_scan(
        .clk  (clk),
        .reset(reset),
        .value(seg_disp),
        .seg  (seg),
        .an   (an)
    );
endmodule
