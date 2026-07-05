`timescale 1ns/1ps
// Fast functional-test testbench (no VCD dump).
module tb_func_fast;
  reg aclk=0, aresetn=0;
  wire [31:0] seg_disp, cnt_value;
  wire [31:0] num_data;
  wire [15:0] led;
  wire [1:0]  led_rg0, led_rg1;
  integer cyc = 0;

  soc_top #(.INIT_FILE("sw/func.mem")) dut(
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
      $display("[%0t] num_data <= 0x%08x  led=%04x led_rg0=%b led_rg1=%b",
               $time, num_data, led, led_rg0, led_rg1);
      num_prev   <= num_data;
      num_stable <= 32'd0;
    end else begin
      num_stable <= num_stable + 1;
    end
  end

  initial begin
    repeat (4) @(negedge aclk);
    aresetn = 1;
    for (cyc=0; cyc<10_000_000; cyc=cyc+1) begin
      @(negedge aclk);
      if (num_data !== 32'h0 && num_stable >= 100_000) begin
        $display("program reached steady state at cyc=%0d", cyc);
        if (num_data === 32'h3a00003a && led_rg0 === 2'b01 && led_rg1 === 2'b01)
          $display("PASS tb_func_fast");
        else
          $display("FAIL tb_func_fast: num_data=0x%08x led_rg0=%b led_rg1=%b",
                   num_data, led_rg0, led_rg1);
        $finish;
      end
    end
    $display("WARN: hit 10M cap");
    $display("final num_data=0x%08x led_rg0=%b led_rg1=%b", num_data, led_rg0, led_rg1);
    $finish;
  end
endmodule
