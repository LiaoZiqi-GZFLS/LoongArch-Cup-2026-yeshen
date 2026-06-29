`timescale 1ns/1ps
// Run from the soc/ directory (so $readmemh resolves "sw/demo.mem"):
//   cd soc
//   xvlog -d SIMU -i rtl/core rtl/core/*.v rtl/soc/*.v rtl/periph/*.v sim/tb_soc.v
//   xelab tb_soc -s tb_soc_sim --debug typical
//   xsim tb_soc_sim -R
//
// INIT_FILE is relative to the simulator cwd (soc/), keeping the TB portable.

module tb_soc;
  reg aclk=0, aresetn=0;
  wire [31:0] seg_disp, cnt_value;
  reg  [31:0] seen_sum = 32'hffffffff;
  integer cyc = 0;

  soc_top #(.INIT_FILE("sw/demo.mem")) dut(
    .aclk(aclk), .aresetn(aresetn), .seg_disp(seg_disp), .cnt_value(cnt_value));

  always #5 aclk = ~aclk;

  reg [31:0] seg_prev = 32'b0;
  always @(posedge aclk) begin
    if (aresetn && seg_disp != seg_prev) begin
      $display("[%0t] seg_disp <= 0x%08x (cnt=%0d)", $time, seg_disp, cnt_value);
      if (seg_disp == 32'h37) seen_sum = 32'h37;
      seg_prev <= seg_disp;
    end
  end

  initial begin
    $dumpfile("build/tb_soc.vcd"); $dumpvars(0, tb_soc);
    repeat (4) @(negedge aclk);
    aresetn = 1;
    for (cyc=0; cyc<20000; cyc=cyc+1) @(negedge aclk);
    $display("final seg_disp=0x%08x cnt=%0d seen_sum=0x%08x", seg_disp, cnt_value, seen_sum);
    if (seen_sum !== 32'h37) begin
      $display("FAIL: sum 0x37 never displayed (program did not compute 1..10)");
      $finish;
    end
    if (seg_disp === 32'h0 || seg_disp === 32'h37) begin
      $display("FAIL: final seg_disp not updated to cycle count (got 0x%08x)", seg_disp);
      $finish;
    end
    $display("PASS tb_soc");
    $finish;
  end
endmodule
