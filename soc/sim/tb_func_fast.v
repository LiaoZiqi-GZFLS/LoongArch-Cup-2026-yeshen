`timescale 1ns/1ps
// Backward-compatible fast functional-test testbench.
// It is now a thin wrapper around tb_soc_generic so the pass/fail logic and
// optional diagnostics live in one place.
module tb_func_fast;
  tb_soc_generic #(
    .INIT_FILE("sw/func.mem"),
    .TIMEOUT_CYCLES(10_000_000),
    .STABLE_CYCLES(100_000),
    .EXPECT_NUM_DATA(32'h3a00003a),
    .EXPECT_LED_RG0(2'b01),
    .EXPECT_LED_RG1(2'b01)
  ) u_tb ();
endmodule
