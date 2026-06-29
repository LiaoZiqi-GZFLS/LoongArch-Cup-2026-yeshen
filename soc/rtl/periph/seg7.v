`timescale 1ns/1ps
// Memory-mapped 8-digit seven-segment display register at 0x1fb0_0000 (write).
// Holds a 32-bit value = 8 hex nibbles. In simulation we observe `disp`.
// Board-level segment encoding / digit scanning is out of scope for this demo.
module seg7(
    input             clk,
    input             reset,
    input             we,
    input  [31:0]     wdata,
    output reg [31:0] disp
);
always @(posedge clk) begin
    if (reset)   disp <= 32'd0;
    else if (we) disp <= wdata;
end
endmodule
