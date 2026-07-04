`timescale 1ns/1ps
// Functional-test testbench for the 2026 LoongArch Cup ChipLab package.
// Loads nscscc_func/obj/main.bin (via sw/func.mem) and checks the official
// pass/fail display rules on the nscscc-team confreg module:
//   PASS: num_data == 0x3a00003a, led_rg0/1 both green (2'b01)
//   FAIL: monochrome LEDs all on, led_rg0/1 both red (2'b10), num_data high/low bytes differ.
//
// Run from the soc/ directory:
//   iverilog -g2012 -DSIM_NO_PLL -I rtl/core rtl/core/*.v rtl/soc/*.v rtl/periph/*.v sim/tb_func.v -o build/tb_func.out
//   vvp build/tb_func.out
module tb_func;
  reg aclk=0, aresetn=0;
  wire [31:0] seg_disp, cnt_value;
  wire [31:0] num_data;
  wire [15:0] led;
  wire [1:0]  led_rg0, led_rg1;
  integer cyc = 0;

  // Tie board inputs so idle_1s delay becomes minimal (switch all-up = 0xff).
  soc_top #(.INIT_FILE("sw/func.mem")) dut(
    .aclk(aclk), .aresetn(aresetn), .seg_disp(seg_disp), .cnt_value(cnt_value),
    .num_data(num_data), .led(led), .led_rg0(led_rg0), .led_rg1(led_rg1),
    .num_csn(), .num_a_g(),
    .switch(8'hff), .btn_key_row(4'hf), .btn_step(2'b11)
  );

  always #5 aclk = ~aclk;

  // Track the last time num_data changed; stable final value means done.
  reg [31:0] num_prev = 32'h0;
  reg [31:0] num_stable = 32'h0;
  reg        mono_fail = 1'b0;

  always @(posedge aclk) if (aresetn) begin
    if (num_data !== num_prev) begin
      $display("[%0t] num_data <= 0x%08x  led=%04x led_rg0=%b led_rg1=%b", $time, num_data, led, led_rg0, led_rg1);
      num_prev   <= num_data;
      num_stable <= 32'd0;
    end else begin
      num_stable <= num_stable + 1;
    end
  end

  task do_final_checks;
    begin
      $display("final num_data=0x%08x led=%04x led_rg0=%b led_rg1=%b", num_data, led, led_rg0, led_rg1);
      if (num_data === 32'h3a00003a && led_rg0 === 2'b01 && led_rg1 === 2'b01)
        $display("PASS tb_func: functional test passed (num_data=0x3a00003a, both RG LEDs green)");
      else begin
        $display("FAIL tb_func: expected num_data=0x3a00003a with led_rg0/1=2'b01");
        $display("             got num_data=0x%08x led_rg0=%b led_rg1=%b", num_data, led_rg0, led_rg1);
      end
      $finish;
    end
  endtask

  initial begin
    $dumpfile("build/tb_func.vcd"); $dumpvars(0, tb_func);
    repeat (4) @(negedge aclk);
    aresetn = 1;
    // Run until the display value has been stable for a long time, or until a
    // generous safety cap.  With switch=0xff idle delays are tiny, but each
    // individual test can run for many thousands of cycles between confreg
    // updates, so the stable threshold must be larger than a single test.
    for (cyc=0; cyc<10_000_000; cyc=cyc+1) begin
      @(negedge aclk);
      if (num_data !== 32'h0 && num_stable >= 100_000) begin
        $display("program reached steady state (num_data stable %0d cycles) at cyc=%0d", num_stable, cyc);
        do_final_checks;
      end
    end
    $display("WARN: hit 10M-cycle safety cap");
    do_final_checks;
  end
endmodule
