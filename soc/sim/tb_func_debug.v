`timescale 1ns/1ps
// Debug functional-test testbench with diagnostics and VCD dump enabled.
module tb_func_debug;
  initial begin
    $dumpfile("build/tb_func_debug.vcd");
    $dumpvars(0, tb_func_debug);
  end

  tb_soc_generic #(
    .INIT_FILE("sw/func.mem"),
    .TIMEOUT_CYCLES(7_000_000),
    .STABLE_CYCLES(100_000),
    .EXPECT_NUM_DATA(32'h3a00003a),
    .EXPECT_LED_RG0(2'b01),
    .EXPECT_LED_RG1(2'b01),
    .ENABLE_DIAG(1'b1),
    .DUMP_HANG(1'b1)
  ) u_tb ();
endmodule
