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
    .switch(8'h1e), .btn_key_row(4'hf), .btn_step(2'b11)
  );

  always #5 aclk = ~aclk;

  reg [31:0] num_prev = 32'h0;
  reg [31:0] num_stable = 32'd0;

  // Exception trap to diagnose the first exception that jumps to EENTRY.
  wire        ws_excp     = dut.u_core.wb_stage.excp_flush;
  wire [31:0] ws_excp_num = dut.u_core.wb_stage.ws_excp_num;
  wire [31:0] ws_pc       = dut.u_core.wb_stage.ws_pc;
  wire [31:0] ws_error_va = dut.u_core.wb_stage.ws_error_va;
  always @(posedge aclk) if (aresetn && ws_excp) begin
    $display("[%0t] EXCEPTION at cyc=%0d ws_pc=%08x excp_num=%08x ws_error_va=%08x num=%08x",
             $time, cyc, ws_pc, ws_excp_num, ws_error_va, num_data);
    $display("pipeline: if=%08x fs=%08x ds=%08x es=%08x ms=%08x ws=%08x ws_valid=%b",
             dut.u_core.if_stage.nextpc, dut.u_core.if_stage.fs_pc,
             dut.u_core.id_stage.ds_pc, dut.u_core.exe_stage.es_pc,
             dut.u_core.mem_stage.ms_pc, dut.u_core.wb_stage.ws_pc,
             dut.u_core.ws_valid);
    $finish;
  end

  reg [31:0] stuck_pc = 32'h0;
  reg [31:0] stuck_cnt = 32'h0;
  reg        hang_dumped = 1'b0;

  always @(posedge aclk) if (aresetn) begin
    if (num_data !== num_prev) begin
      $display("[%0t] num_data <= 0x%08x  led=%04x led_rg0=%b led_rg1=%b", $time, num_data, led, led_rg0, led_rg1);
      $fflush;
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
      $fflush;
    end
    // hang detector: nextpc unchanged for a long time while num_data stays zero
    if (dut.u_core.if_stage.nextpc == stuck_pc) begin
      stuck_cnt <= stuck_cnt + 1;
    end else begin
      stuck_pc  <= dut.u_core.if_stage.nextpc;
      stuck_cnt <= 32'd1;
    end
    if (!hang_dumped && stuck_cnt >= 32'd10000 && num_data == 32'h0) begin
      hang_dumped <= 1'b1;
      $display("\n=== HANG DETECTED at cyc=%0d nextpc=%08x ===", cyc, stuck_pc);
      $display("pipeline: if(nextpc)=%08x fs=%08x ds=%08x es=%08x ms=%08x ws=%08x",
               dut.u_core.if_stage.nextpc, dut.u_core.if_stage.fs_pc,
               dut.u_core.id_stage.ds_pc, dut.u_core.exe_stage.es_pc,
               dut.u_core.mem_stage.ms_pc, dut.u_core.wb_stage.ws_pc);
      $display("stage valid: fs=%b ds=%b es=%b ms=%b ws=%b",
               dut.u_core.if_stage.fs_valid, dut.u_core.id_stage.ds_valid,
               dut.u_core.exe_stage.es_valid, dut.u_core.mem_stage.ms_valid,
               dut.u_core.wb_stage.ws_valid);
      $display("stage ready_go: fs=%b ds=%b es=%b ms=%b ws=%b",
               dut.u_core.if_stage.fs_ready_go, dut.u_core.id_stage.ds_ready_go,
               dut.u_core.exe_stage.es_ready_go, dut.u_core.mem_stage.ms_ready_go, dut.u_core.wb_stage.ws_ready_go);
      $display("allowin: ds=%b es=%b ms=%b ws=%b",
               dut.u_core.id_stage.ds_allowin, dut.u_core.exe_stage.es_allowin,
               dut.u_core.mem_stage.ms_allowin, dut.u_core.wb_stage.ws_allowin);
      $display("AXI master: arvalid=%b arready=%b araddr=%08x arlen=%02x rvalid=%b rready=%b",
               dut.arvalid, dut.arready, dut.araddr, dut.arlen, dut.rvalid, dut.rready);
      $display("AXI master: awvalid=%b awready=%b awaddr=%08x awlen=%02x wvalid=%b wready=%b wlast=%b",
               dut.awvalid, dut.awready, dut.awaddr, dut.awlen, dut.wvalid, dut.wready, dut.wlast);
      $display("AXI slave0 (mem): arvalid=%b arready=%b araddr=%08x rvalid=%b rready=%b",
               dut.s0_arvalid, dut.s0_arready, dut.s0_araddr, dut.s0_rvalid, dut.s0_rready);
      $display("AXI slave0 (mem): awvalid=%b awready=%b awaddr=%08x wvalid=%b wready=%b wlast=%b bvalid=%b bready=%b",
               dut.s0_awvalid, dut.s0_awready, dut.s0_awaddr, dut.s0_wvalid, dut.s0_wready, dut.s0_wlast, dut.s0_bvalid, dut.s0_bready);
      $display("mem FSM: rstate=%0d wstate=%0d", dut.u_mem.rstate, dut.u_mem.wstate);
      $display("heap __curbrk(0x1c0bf4f0)=%08x __heap_end(0x1c0bf79c)=%08x",
               dut.u_mem.mem[(32'h1c0bf4f0 - 32'h1c00_0000) >> 2],
               dut.u_mem.mem[(32'h1c0bf79c - 32'h1c00_0000) >> 2]);
      $display("free_list(0x1c0bf484)=%08x", dut.u_mem.mem[(32'h1c0bf484 - 32'h1c00_0000) >> 2]);
      $display("icache main_state=%05b dcache main_state=%05b dcache_wr_state=%b", dut.u_core.icache.main_state, dut.u_core.dcache.main_state, dut.u_core.dcache.write_buffer_state);
      $display("bridge rd_req_state=%b read_resp_state=%b wr_state=%0d write_wait_enable=%b",
               dut.u_core.axi_bridge.read_requst_state, dut.u_core.axi_bridge.read_respond_state,
               dut.u_core.axi_bridge.write_requst_state, dut.u_core.axi_bridge.write_wait_enable);
      $display("bridge inst_rd_req=%b inst_rd_rdy=%b inst_rd_addr=%08x data_rd_req=%b data_rd_rdy=%b data_rd_addr=%08x",
               dut.u_core.axi_bridge.inst_rd_req, dut.u_core.axi_bridge.inst_rd_rdy, dut.u_core.axi_bridge.inst_rd_addr,
               dut.u_core.axi_bridge.data_rd_req, dut.u_core.axi_bridge.data_rd_rdy, dut.u_core.axi_bridge.data_rd_addr);
      $display("bridge data_wr_req=%b data_wr_rdy=%b data_wr_addr=%08x",
               dut.u_core.axi_bridge.data_wr_req, dut.u_core.axi_bridge.data_wr_rdy, dut.u_core.axi_bridge.data_wr_addr);
      $display("if_stage: inst_valid=%b inst_addr_ok=%b inst_data_ok=%b pfs_ready_go=%b to_fs_valid=%b",
               dut.u_core.if_stage.inst_valid, dut.u_core.if_stage.inst_addr_ok,
               dut.u_core.if_stage.inst_data_ok, dut.u_core.if_stage.pfs_ready_go,
               dut.u_core.if_stage.to_fs_valid);
      $display("if_stage: fs_allowin=%b inst_uncache_en=%b pfs_excp=%b fs_excp=%b tlb_excp_cancel=%b idle_lock=%b flush_sign=%b",
               dut.u_core.if_stage.fs_allowin, dut.u_core.if_stage.inst_uncache_en,
               dut.u_core.if_stage.pfs_excp, dut.u_core.if_stage.fs_excp,
               dut.u_core.if_stage.tlb_excp_cancel_req, dut.u_core.if_stage.idle_lock,
               dut.u_core.if_stage.flush_sign);
      $display("if_fsm: br_state=%03b flush_state=%b btb_pre_error=%b",
               dut.u_core.if_stage.br_target_inst_req_state,
               dut.u_core.if_stage.flush_inst_req_state,
               dut.u_core.if_stage.btb_pre_error_flush);
      $display("core arvalid=%b arready=%b araddr=%08x arid=%x awvalid=%b awready=%b awaddr=%08x wvalid=%b wready=%b bvalid=%b bready=%b",
               dut.arvalid, dut.arready, dut.araddr, dut.arid, dut.awvalid, dut.awready, dut.awaddr, dut.wvalid, dut.wready, dut.bvalid, dut.bready);
      $finish;
    end
  end

  // Trace every AXI R beat to verify burst length.
  always @(posedge aclk) if (aresetn && dut.rvalid && dut.rready) begin
    $display("[rbeat] cyc=%0d rid=%x rdata=%08x rlast=%b araddr=%08x arlen=%02x",
             cyc, dut.rid, dut.rdata, dut.rlast, dut.araddr, dut.arlen);
    $fflush;
  end

  // Trace the cycles just before the hang to see the transition.
  reg [31:0] trace_cnt = 32'd0;
  always @(posedge aclk) if (aresetn) begin
    if (dut.u_core.if_stage.fs_pc == 32'h1c0312bc && trace_cnt < 32'd80) begin
      $display("[trace-%0d] cyc=%0d nextpc=%08x fs_pc=%08x fs_valid=%b fs_ready_go=%b inst_valid=%b inst_addr_ok=%b inst_data_ok=%b icache_state=%05b",
               trace_cnt, cyc, dut.u_core.if_stage.nextpc, dut.u_core.if_stage.fs_pc,
               dut.u_core.if_stage.fs_valid, dut.u_core.if_stage.fs_ready_go,
               dut.u_core.if_stage.inst_valid, dut.u_core.if_stage.inst_addr_ok,
               dut.u_core.if_stage.inst_data_ok, dut.u_core.icache.main_state);
      $display("        axi_r: valid=%b ready=%b last=%b data=%08x araddr=%08x arlen=%02x",
               dut.rvalid, dut.rready, dut.rlast, dut.rdata, dut.araddr, dut.arlen);
      $display("        bridge: inst_ret_valid=%b inst_ret_last=%b inst_ret_data=%08x",
               dut.u_core.axi_bridge.inst_ret_valid, dut.u_core.axi_bridge.inst_ret_last,
               dut.u_core.axi_bridge.inst_ret_data);
      $display("        bridge_state: rd_req=%b rd_resp=%b arvalid=%b arready=%b araddr=%08x arid=%x",
               dut.u_core.axi_bridge.read_requst_state, dut.u_core.axi_bridge.read_respond_state,
               dut.arvalid, dut.arready, dut.araddr, dut.arid);
      $display("        icache: ret_num=%0d req_offset=%0d(%0d) data_ok=%b rd_req=%b rd_rdy=%b rd_addr=%08x rd_req_buffer=%b",
               dut.u_core.icache.miss_buffer_ret_num, dut.u_core.icache.request_buffer_offset,
               dut.u_core.icache.request_buffer_offset[3:2], dut.u_core.icache.data_ok,
               dut.u_core.icache.rd_req, dut.u_core.icache.rd_rdy, dut.u_core.icache.rd_addr,
               dut.u_core.icache.rd_req_buffer);
      $fflush;
      trace_cnt <= trace_cnt + 1;
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
