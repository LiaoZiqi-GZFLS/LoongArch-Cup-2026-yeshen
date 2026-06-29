`timescale 1ns/1ps
module tb_seg7;
  reg clk = 0, reset = 1, we = 0;
  reg  [31:0] wdata = 0;
  wire [31:0] disp;
  seg7 dut(.clk(clk), .reset(reset), .we(we), .wdata(wdata), .disp(disp));
  always #5 clk = ~clk;
  initial begin
    @(negedge clk); reset = 0;
    if (disp !== 32'd0) begin $display("FAIL reset disp=%h", disp); $finish; end
    wdata = 32'h00000037; we = 1; @(negedge clk); we = 0;  // write 0x37 (=55)
    if (disp !== 32'h00000037) begin $display("FAIL after we disp=%h", disp); $finish; end
    wdata = 32'hDEADBEEF; @(negedge clk);                  // no we -> hold
    if (disp !== 32'h00000037) begin $display("FAIL held disp=%h", disp); $finish; end
    $display("PASS tb_seg7");
    $finish;
  end
endmodule
