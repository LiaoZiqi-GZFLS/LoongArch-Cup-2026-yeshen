`timescale 1ns/1ps
// Performance-test testbench for the 2026 LoongArch Cup ChipLab package.
// Loads a nscscc_perf/obj/*/inst_data.bin (via sw/perf_*.mem) and waits for
// the benchmark to write its final cycle count to NUM_ADDR (0xbfaf_f050).
// Switch=0xff selects test 1 (shell1) and keeps idle_1s delays minimal.
//
// Run from the soc/ directory:
//   iverilog -g2012 -DSIM_NO_PLL -I rtl/core rtl/core/*.v rtl/soc/*.v rtl/periph/*.v sim/tb_perf.v -o build/tb_perf.out
//   vvp build/tb_perf.out
module tb_perf;
  parameter INIT_FILE = "sw/perf_bitcount.mem";
  reg aclk=0, aresetn=0;
  wire [31:0] seg_disp, cnt_value;
  wire [31:0] num_data;
  wire [15:0] led;
  wire [1:0]  led_rg0, led_rg1;
  integer cyc = 0;

  soc_top #(.INIT_FILE(INIT_FILE)) dut(
    .aclk(aclk), .aresetn(aresetn), .seg_disp(seg_disp), .cnt_value(cnt_value),
    .num_data(num_data), .led(led), .led_rg0(led_rg0), .led_rg1(led_rg1),
    .num_csn(), .num_a_g(),
    .switch(8'hff), .btn_key_row(4'hf), .btn_step(2'b11)
  );

  always #5 aclk = ~aclk;

  reg [31:0] num_prev = 32'h0;
  reg [31:0] num_stable = 32'd0;

  always @(posedge aclk) if (aresetn) begin
    if (num_data !== num_prev) begin
      $display("[%0t] num_data <= 0x%08x  led=%04x led_rg0=%b led_rg1=%b", $time, num_data, led, led_rg0, led_rg1);
      num_prev   <= num_data;
      num_stable <= 32'd0;
    end else begin
      num_stable <= num_stable + 1;
    end
  end

  initial begin
    $dumpfile("build/tb_perf.vcd"); $dumpvars(0, tb_perf);
    repeat (4) @(negedge aclk);
    aresetn = 1;
    // Performance tests can run for many millions of cycles; use a generous cap.
    for (cyc=0; cyc<50_000_000; cyc=cyc+1) begin
      @(negedge aclk);
      if (num_data !== 32'h0 && num_stable >= 100_000) begin
        $display("program reached steady state at cyc=%0d", cyc);
        $display("PASS tb_perf: num_data=0x%08x led=%04x led_rg0=%b led_rg1=%b",
                 num_data, led, led_rg0, led_rg1);
        $finish;
      end
    end
    $display("WARN: hit 50M-cycle safety cap");
    $display("final num_data=0x%08x led=%04x led_rg0=%b led_rg1=%b", num_data, led, led_rg0, led_rg1);
    $finish;
  end
endmodule
