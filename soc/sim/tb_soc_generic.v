`timescale 1ns/1ps
// Generic SoC testbench.  Per-test wrappers set INIT_FILE and the pass/fail
// criteria.  Optional diagnostics (exception trap, periodic PC dump, hang
// detector, AXI R-beat trace) are gated by ENABLE_DIAG and are modelled on
// the legacy soc/sim/tb_perf_fast.v diagnostics block.
module tb_soc_generic #(
    parameter INIT_FILE                  = "",
    parameter TIMEOUT_CYCLES             = 10_000_000,
    parameter STABLE_CYCLES              = 100_000,
    parameter EXPECT_NUM_DATA            = 32'h0,        // 0 -> don't care
    parameter EXPECT_LED_RG0             = 2'b00,        // 00 -> don't care
    parameter EXPECT_LED_RG1             = 2'b00,        // 00 -> don't care
    parameter REQUIRE_NUM_DATA_NONZERO   = 1'b0,
    parameter ENABLE_DIAG                = 1'b0,
    parameter DUMP_HANG                  = 1'b0
)(
    // no ports
);
  reg aclk=0, aresetn=0;
  wire [31:0] seg_disp, cnt_value;
  wire [31:0] num_data;
  wire [15:0] led;
  wire [1:0]  led_rg0, led_rg1;
  integer cyc = 0;

  // The current soc_top exposes a single aclk/aresetn interface and the
  // board-level I/O bundle; DDR/UART pins from the integration skeleton are
  // therefore omitted here.
  soc_top #(.INIT_FILE(INIT_FILE)) dut(
    .aclk(aclk), .aresetn(aresetn), .seg_disp(seg_disp), .cnt_value(cnt_value),
    .num_data(num_data), .led(led), .led_rg0(led_rg0), .led_rg1(led_rg1),
    .num_csn(), .num_a_g(),
    .switch(8'hff), .btn_key_row(4'hf), .btn_step(2'b11)
  );

  always #5 aclk = ~aclk;

  // Runtime overrides (plusargs win over parameters)
  integer timeout_cycles;
  integer stable_cycles;
  integer expect_num_data;
  integer expect_led_rg0;
  integer expect_led_rg1;
  integer require_num_data_nonzero;
  integer enable_diag;
  integer dump_hang;

  initial begin
    timeout_cycles           = TIMEOUT_CYCLES;
    stable_cycles            = STABLE_CYCLES;
    expect_num_data          = EXPECT_NUM_DATA;
    expect_led_rg0           = EXPECT_LED_RG0;
    expect_led_rg1           = EXPECT_LED_RG1;
    require_num_data_nonzero = REQUIRE_NUM_DATA_NONZERO;
    enable_diag              = ENABLE_DIAG;
    dump_hang                = DUMP_HANG;

    $value$plusargs("TIMEOUT_CYCLES=%d", timeout_cycles);
    $value$plusargs("STABLE_CYCLES=%d",  stable_cycles);
    $value$plusargs("EXPECT_NUM_DATA=%d", expect_num_data);
    $value$plusargs("EXPECT_LED_RG0=%d",  expect_led_rg0);
    $value$plusargs("EXPECT_LED_RG1=%d",  expect_led_rg1);
    $value$plusargs("REQUIRE_NUM_DATA_NONZERO=%d", require_num_data_nonzero);
    $value$plusargs("ENABLE_DIAG=%d", enable_diag);
    $value$plusargs("DUMP_HANG=%d", dump_hang);
  end

  reg [31:0] num_prev = 32'h0;
  reg [31:0] num_stable = 32'd0;
  reg        done = 1'b0;

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

  function automatic bit pass_ok();
    if (require_num_data_nonzero != 0)
      return (num_data !== 32'h0);
    if (expect_num_data !== 32'h0 && num_data !== expect_num_data[31:0])
      return 1'b0;
    if (expect_led_rg0 !== 2'b00 && led_rg0 !== expect_led_rg0[1:0])
      return 1'b0;
    if (expect_led_rg1 !== 2'b00 && led_rg1 !== expect_led_rg1[1:0])
      return 1'b0;
    return 1'b1;
  endfunction

  // -----------------------------------------------------------------
  // Optional diagnostics: modelled on soc/sim/tb_perf_fast.v.  Every
  // $display is gated by (enable_diag != 0); the wire declarations are
  // always computed so the hierarchy is still exercised when quiet.
  // -----------------------------------------------------------------

  // Exception trap
  wire        ws_excp       = dut.u_core.wb_stage.excp_flush;
  wire [15:0] ws_excp_num   = dut.u_core.wb_stage.ws_excp_num;
  wire [31:0] ws_pc         = dut.u_core.wb_stage.ws_pc;
  wire [31:0] ws_error_va   = dut.u_core.wb_stage.ws_error_va;

  always @(posedge aclk) if (aresetn && ws_excp) begin
    if (enable_diag != 0)
      $display("[%0t] EXCP at ws_pc=%08x num=%04x badva=%08x",
               $time, ws_pc, ws_excp_num, ws_error_va);
  end

  // Periodic PC dump
  always @(posedge aclk) if (aresetn) begin
    if (cyc[19:0] == 20'd0) begin  // every 1M cycles
      if (enable_diag != 0)
        $display("[%0t] cyc=%0d pc=%08x num=%08x r12=%08x r13=%08x r15=%08x",
                 $time, cyc, dut.u_core.if_stage.nextpc, num_data,
                 dut.u_core.id_stage.u_regfile.rf[12],
                 dut.u_core.id_stage.u_regfile.rf[13],
                 dut.u_core.id_stage.u_regfile.rf[15]);
    end
  end

  // Hang detector
  reg [31:0] stuck_pc;
  reg [31:0] stuck_cnt;
  reg        hang_dumped;

  always @(posedge aclk) begin
    if (!aresetn) begin
      stuck_pc    <= 32'h0;
      stuck_cnt   <= 32'd0;
      hang_dumped <= 1'b0;
    end else begin
      if (dut.u_core.if_stage.nextpc !== stuck_pc) begin
        stuck_pc  <= dut.u_core.if_stage.nextpc;
        stuck_cnt <= 32'd0;
      end else begin
        stuck_cnt <= stuck_cnt + 1;
      end
      if (stuck_cnt > STABLE_CYCLES && !hang_dumped) begin
        if (enable_diag != 0)
          $display("[%0t] HANG suspected: nextpc=%08x stuck for %0d cycles",
                   $time, stuck_pc, stuck_cnt);
        hang_dumped <= 1'b1;
      end
    end
  end

  // AXI R-beat trace (core master R channel inside soc_top)
  always @(posedge aclk) if (aresetn) begin
    if (dut.rvalid && dut.rready) begin
      if (enable_diag != 0)
        $display("[%0t] AXI R: rid=%h rdata=%08x rlast=%b",
                 $time, dut.rid, dut.rdata, dut.rlast);
    end
  end

  initial begin
    repeat (4) @(negedge aclk);
    aresetn = 1;
    for (cyc=0; cyc<timeout_cycles; cyc=cyc+1) begin
      @(negedge aclk);
      if (num_data !== 32'h0 && num_stable >= stable_cycles) begin
        $display("program reached steady state at cyc=%0d", cyc);
        if (pass_ok())
          $display("PASS tb_soc_generic: num_data=0x%08x led=%04x led_rg0=%b led_rg1=%b",
                   num_data, led, led_rg0, led_rg1);
        else
          $display("FAIL tb_soc_generic: num_data=0x%08x led_rg0=%b led_rg1=%b",
                   num_data, led_rg0, led_rg1);
        done = 1'b1;
        $finish;
      end
    end
    $display("TIMEOUT tb_soc_generic at cyc=%0d", cyc);
    if (dump_hang != 0) begin
      $display("final num_data=0x%08x led=%04x led_rg0=%b led_rg1=%b",
               num_data, led, led_rg0, led_rg1);
      $display("final IF/nextpc=%08x fs=%08x ds=%08x es=%08x ms=%08x ws=%08x",
               dut.u_core.if_stage.nextpc, dut.u_core.if_stage.fs_pc,
               dut.u_core.id_stage.ds_pc, dut.u_core.exe_stage.es_pc,
               dut.u_core.mem_stage.ms_pc, dut.u_core.wb_stage.ws_pc);
    end
    $finish;
  end
endmodule
