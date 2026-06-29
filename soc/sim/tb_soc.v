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

  // ---- monitors ----
  reg [31:0] seg_prev  = 32'b0;
  reg [31:0] cnt_prev  = 32'b0;
  reg        cnt_seen  = 1'b0;     // have a valid cnt_prev to compare against
  integer    seg_stable = 0;       // cycles seg_disp has held its current value
  reg        mono_fail = 1'b0;

  always @(posedge aclk) if (aresetn) begin
    // (1) cycle counter must be monotonically non-decreasing (spec: cnt grows over time)
    if (cnt_seen && cnt_value < cnt_prev) begin
      $display("FAIL: cnt_value not monotonic: 0x%08x < prev 0x%08x", cnt_value, cnt_prev);
      mono_fail <= 1'b1;
    end
    cnt_prev <= cnt_value;
    cnt_seen <= 1'b1;

    // (2) track seg_disp changes; latch the sum=0x37 transient
    if (seg_disp != seg_prev) begin
      $display("[%0t] seg_disp <= 0x%08x (cnt=%0d)", $time, seg_disp, cnt_value);
      if (seg_disp == 32'h37) seen_sum = 32'h37;
      seg_prev   <= seg_disp;
      seg_stable <= 0;
    end else begin
      seg_stable <= seg_stable + 1;
    end
  end

  // ---- completion detection + checks ----
  // The program ends in `b .`; once seg_disp holds steady for STABLE_DONE cycles
  // (after the final cycle-count write), we treat the program as finished.
  localparam STABLE_DONE = 200;

  task do_final_checks;
    begin
      $display("final seg_disp=0x%08x cnt=%0d seen_sum=0x%08x", seg_disp, cnt_value, seen_sum);
      if (mono_fail)                  begin $display("FAIL: cnt_value monotonicity violated"); $finish; end
      if (seen_sum !== 32'h37)        begin $display("FAIL: sum 0x37 never displayed (program did not compute 1..10)"); $finish; end
      // final seg_disp is the cycle-count delta: must be a real count, i.e. > sum (0x37), never 0
      if (seg_disp === 32'h0 || seg_disp === 32'h37 || seg_disp <= 32'h37)
                                      begin $display("FAIL: final seg_disp not a plausible cycle count (got 0x%08x)", seg_disp); $finish; end
      $display("PASS tb_soc");
      $finish;
    end
  endtask

  initial begin
    $dumpfile("build/tb_soc.vcd"); $dumpvars(0, tb_soc);
    repeat (4) @(negedge aclk);
    aresetn = 1;
    // run until the program settles into its done-loop, or until the safety cap
    for (cyc=0; cyc<20000; cyc=cyc+1) begin
      @(negedge aclk);
      if (seen_sum === 32'h37 && seg_stable >= STABLE_DONE) begin
        $display("program reached done-loop (seg_disp stable %0d cycles) at cyc=%0d", seg_stable, cyc);
        do_final_checks;
      end
    end
    $display("WARN: hit 20000-cycle safety cap without detecting done-loop");
    do_final_checks;
  end
endmodule
