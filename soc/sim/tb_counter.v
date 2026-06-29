`timescale 1ns/1ps
module tb_counter;
  reg clk = 0, reset = 1;
  wire [31:0] cnt;
  integer i;
  counter dut(.clk(clk), .reset(reset), .cycle_cnt(cnt));
  always #5 clk = ~clk;
  initial begin
    @(negedge clk); reset = 1;          // hold reset 1 cycle
    @(negedge clk); reset = 0;
    if (cnt !== 32'd0) begin $display("FAIL: reset cnt=%0d", cnt); $finish; end
    for (i = 0; i < 10; i = i + 1) @(negedge clk);
    if (cnt !== 32'd10) begin $display("FAIL: after 10 clks cnt=%0d (want 10)", cnt); $finish; end
    $display("PASS tb_counter");
    $finish;
  end
endmodule
