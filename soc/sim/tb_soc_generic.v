`timescale 1ns/1ps
// Generic SoC testbench.  Per-test wrappers set INIT_FILE and the pass/fail
// criteria.  Progress messages and optional diagnostics (exception trap,
// periodic PC dump, hang detector, AXI R-beat trace) are gated by ENABLE_DIAG;
// PASS/FAIL/TIMEOUT and hang dumps are always printed.  Runtime plusarg
// overrides use decimal format (%d).  Diagnostics are modelled on the legacy
// soc/sim/tb_perf_fast.v diagnostics block.
module tb_soc_generic #(
    parameter INIT_FILE                  = "",
    parameter TIMEOUT_CYCLES             = 10_000_000,
    parameter STABLE_CYCLES              = 100_000,
    parameter RESET_CYCLES               = 4,
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
    expect_led_rg0           = {{30{1'b0}}, EXPECT_LED_RG0};
    expect_led_rg1           = {{30{1'b0}}, EXPECT_LED_RG1};
    require_num_data_nonzero = {31'b0, REQUIRE_NUM_DATA_NONZERO};
    enable_diag              = {31'b0, ENABLE_DIAG};
    dump_hang                = {31'b0, DUMP_HANG};

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
  reg        test_done = 1'b0;

  always @(posedge aclk) if (aresetn) begin
    if (num_data !== num_prev) begin
      if (enable_diag != 0)
        $display("[%0t] num_data <= 0x%08x  led=%04x led_rg0=%b led_rg1=%b",
                 $time, num_data, led, led_rg0, led_rg1);
      num_prev   <= num_data;
      num_stable <= 32'd0;
    end else begin
      num_stable <= num_stable + 1;
    end
  end

  function reg pass_ok;
    begin
      pass_ok = 1'b1;
      if (require_num_data_nonzero != 0) begin
        // Reject both zero and unknown (X/Z) values.
        if (num_data == 32'h0 || (^num_data) === 1'bx)
          pass_ok = 1'b0;
      end
      else begin
        if (expect_num_data !== 32'h0 && num_data !== expect_num_data[31:0])
          pass_ok = 1'b0;
        if (expect_led_rg0[1:0] !== 2'b00 && led_rg0 !== expect_led_rg0[1:0])
          pass_ok = 1'b0;
        if (expect_led_rg1[1:0] !== 2'b00 && led_rg1 !== expect_led_rg1[1:0])
          pass_ok = 1'b0;
      end
    end
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

  // ID-stage INE diagnostic: the WB-stage PC is several bubbles away from
  // the actual decoded instruction, so capture ds_pc/ds_inst here.
  wire        id_excp_ine   = dut.u_core.id_stage.excp_ine;
  wire        id_valid      = dut.u_core.id_stage.ds_valid;
  wire [31:0] id_pc         = dut.u_core.id_stage.ds_pc;
  wire [31:0] id_inst       = dut.u_core.id_stage.ds_inst;
  wire        id_inst_valid = dut.u_core.id_stage.inst_valid;
  reg         id_excp_ine_d;
  always @(posedge aclk) id_excp_ine_d <= id_excp_ine;
  always @(posedge aclk) if (aresetn && id_excp_ine && id_valid && !id_excp_ine_d) begin
    if (enable_diag != 0)
      $display("[%0t] INE at id_pc=%08x id_inst=%08x inst_valid=%b",
               $time, id_pc, id_inst, id_inst_valid);
  end

  // Detailed fetch-path snapshot around the bitcount sbrk target.
  // This is temporary instrumentation for the 0x1c004edc INE investigation.
  wire [31:0] if_nextpc     = dut.u_core.if_stage.nextpc;
  wire [31:0] if_fs_pc      = dut.u_core.if_stage.fs_pc;
  wire        if_fs_valid   = dut.u_core.if_stage.fs_valid;
  wire        if_inst_valid = dut.u_core.if_stage.inst_valid;
  wire        if_addr_ok    = dut.u_core.if_stage.inst_addr_ok;
  wire        if_data_ok    = dut.u_core.if_stage.inst_data_ok;
  wire [31:0] if_rdata      = dut.u_core.if_stage.inst_rdata;
  wire        if_buff_en    = dut.u_core.if_stage.inst_buff_enable;
  wire [31:0] if_buff_data  = dut.u_core.if_stage.inst_rd_buff;
  wire [31:0] ic_rdata      = dut.u_core.icache.rdata;
  wire        ic_data_ok    = dut.u_core.icache.data_ok;
  wire        ic_addr_ok    = dut.u_core.icache.addr_ok;
  wire [4:0]  ic_state      = dut.u_core.icache.main_state;
  wire [19:0] ic_req_tag    = dut.u_core.icache.request_buffer_tag;
  wire [7:0]  ic_req_idx    = dut.u_core.icache.request_buffer_index;
  wire [3:0]  ic_req_off    = dut.u_core.icache.request_buffer_offset;
  wire [1:0]  ic_way_hit    = dut.u_core.icache.way_hit;
  wire        ic_cache_hit  = dut.u_core.icache.cache_hit;
  wire [31:0] ic_rd_addr    = dut.u_core.icache.rd_addr;
  wire        fs2ds_valid   = dut.u_core.if_stage.fs_to_ds_valid;
  always @(posedge aclk) begin
    if (aresetn && enable_diag != 0 &&
        ((if_nextpc >= 32'h1c004ed0 && if_nextpc <= 32'h1c004ef0) ||
         (id_pc    >= 32'h1c004ed0 && id_pc    <= 32'h1c004ef0))) begin
      $display("[%0t] FETCH nextpc=%08x fs=%08x fv=%b iv=%b aok=%b dok=%b rdata=%08x buff=%b/%08x | IC st=%b req=%08x/%03x/%x hit=%b/%b ic_rdata=%08x ic_dok=%b ic_aok=%b rd_addr=%08x | AR araddr=%08x arvalid=%b | ID pc=%08x inst=%08x v=%b fs2ds=%b",
               $time, if_nextpc, if_fs_pc, if_fs_valid, if_inst_valid,
               if_addr_ok, if_data_ok, if_rdata, if_buff_en, if_buff_data,
               ic_state, ic_req_tag, ic_req_idx, ic_req_off,
               ic_way_hit, ic_cache_hit, ic_rdata, ic_data_ok, ic_addr_ok, ic_rd_addr,
               dut.araddr, dut.arvalid,
               id_pc, id_inst, id_valid, fs2ds_valid);
    end
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
      if (stuck_cnt >= stable_cycles && !hang_dumped) begin
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
    repeat (RESET_CYCLES) @(negedge aclk);
    aresetn = 1;
    test_done = 1'b0;
    for (cyc=0; cyc<timeout_cycles && !test_done; cyc=cyc+1) begin
      @(negedge aclk);
      if (num_data !== 32'h0 && num_stable >= stable_cycles) begin
        $display("program reached steady state at cyc=%0d", cyc);
        if (pass_ok())
          $display("PASS tb_soc_generic: num_data=0x%08x led=%04x led_rg0=%b led_rg1=%b",
                   num_data, led, led_rg0, led_rg1);
        else
          $display("FAIL tb_soc_generic: num_data=0x%08x led_rg0=%b led_rg1=%b",
                   num_data, led_rg0, led_rg1);
        test_done = 1'b1;
      end
    end
    if (!test_done)
      $display("TIMEOUT tb_soc_generic at cyc=%0d", cyc);
    if (dump_hang != 0 && !test_done) begin
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
