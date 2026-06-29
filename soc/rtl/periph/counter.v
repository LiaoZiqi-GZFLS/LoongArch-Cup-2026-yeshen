`timescale 1ns/1ps
// Free-running 32-bit cycle counter. Memory-mapped read-only at 0x1fb0_0010.
// Program reads it at start/end; difference = run cycles (perf scoring basis).
module counter(
    input             clk,
    input             reset,
    output reg [31:0] cycle_cnt
);
always @(posedge clk) begin
    if (reset) cycle_cnt <= 32'd0;
    else       cycle_cnt <= cycle_cnt + 32'd1;
end
endmodule
