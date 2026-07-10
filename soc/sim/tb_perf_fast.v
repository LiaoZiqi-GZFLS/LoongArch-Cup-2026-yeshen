`timescale 1ns/1ps
// Backward-compatible fast performance-test testbench.
// Defaults to the bitcount benchmark; override INIT_FILE at elaboration time
// if a different performance image is required.
module tb_perf_fast;
  tb_soc_generic #(
    .INIT_FILE("sw/perf_bitcount.mem"),
    .TIMEOUT_CYCLES(500_000_000),
    .STABLE_CYCLES(100_000),
    .REQUIRE_NUM_DATA_NONZERO(1'b1),
    .ENABLE_DIAG(1'b1),
    .DUMP_HANG(1'b1)
  ) u_tb ();
endmodule
