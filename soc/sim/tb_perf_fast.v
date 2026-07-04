`timescale 1ns/1ps
// Fast performance-test testbench (no VCD dump).
module tb_perf_fast;
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
    if (cyc[19:0] == 20'd0) begin  // every 1M cycles
      $display("[%0t] cyc=%0d pc=%08x num=%08x r12=%08x r13=%08x r15=%08x",
               $time, cyc, dut.u_core.if_stage.nextpc, num_data,
               dut.u_core.id_stage.u_regfile.rf[12],
               dut.u_core.id_stage.u_regfile.rf[13],
               dut.u_core.id_stage.u_regfile.rf[15]);
    end
  end

  initial begin
    repeat (4) @(negedge aclk);
    aresetn = 1;
    for (cyc=0; cyc<500_000_000; cyc=cyc+1) begin
      @(negedge aclk);
      if (num_data !== 32'h0 && num_stable >= 100_000) begin
        $display("program reached steady state at cyc=%0d", cyc);
        $display("PASS tb_perf_fast: num_data=0x%08x led=%04x led_rg0=%b led_rg1=%b",
                 num_data, led, led_rg0, led_rg1);
        $finish;
      end
    end
    $display("WARN: hit 500M-cycle safety cap");
    $display("final num_data=0x%08x led=%04x led_rg0=%b led_rg1=%b", num_data, led, led_rg0, led_rg1);
    $display("final IF/nextpc=%08x fs=%08x ds=%08x es=%08x ms=%08x ws=%08x ws_valid=%b",
             dut.u_core.if_stage.nextpc, dut.u_core.if_stage.fs_pc,
             dut.u_core.id_stage.ds_pc, dut.u_core.exe_stage.es_pc,
             dut.u_core.mem_stage.ms_pc, dut.u_core.wb_stage.ws_pc,
             dut.u_core.ws_valid);
    $finish;
  end
endmodule
