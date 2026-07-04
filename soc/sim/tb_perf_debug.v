`timescale 1ns/1ps
// Debug testbench for performance-test hang.
module tb_perf_debug;
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

  wire [31:0] if_nextpc = dut.u_core.if_stage.nextpc;
  wire [31:0] fs_pc     = dut.u_core.if_stage.fs_pc;
  wire [31:0] ds_pc     = dut.u_core.id_stage.ds_pc;
  wire [31:0] es_pc     = dut.u_core.exe_stage.es_pc;
  wire [31:0] ms_pc     = dut.u_core.mem_stage.ms_pc;
  wire [31:0] ws_pc     = dut.u_core.wb_stage.ws_pc;
  wire        ws_valid  = dut.u_core.ws_valid;

  wire        m_arvalid = dut.u_dec.m_arvalid;
  wire        m_arready = dut.u_dec.m_arready;
  wire [31:0] m_araddr  = dut.u_dec.m_araddr;
  wire        m_rvalid  = dut.u_dec.m_rvalid;
  wire        m_rready  = dut.u_dec.m_rready;
  wire [31:0] m_rdata   = dut.u_dec.m_rdata;
  wire        m_rlast   = dut.u_dec.m_rlast;
  wire        m_awvalid = dut.u_dec.m_awvalid;
  wire        m_awready = dut.u_dec.m_awready;
  wire [31:0] m_awaddr  = dut.u_dec.m_awaddr;
  wire        m_wvalid  = dut.u_dec.m_wvalid;
  wire        m_wready  = dut.u_dec.m_wready;
  wire        m_bvalid  = dut.u_dec.m_bvalid;
  wire        m_bready  = dut.u_dec.m_bready;

  wire        s1_arvalid = dut.u_dec.s1_arvalid;
  wire        s1_arready = dut.u_dec.s1_arready;
  wire [31:0] s1_araddr  = dut.u_dec.s1_araddr;
  wire        s1_rvalid  = dut.u_dec.s1_rvalid;
  wire        s1_rready  = dut.u_dec.s1_rready;
  wire [31:0] s1_rdata   = dut.u_dec.s1_rdata;
  wire        s1_rlast   = dut.u_dec.s1_rlast;
  wire        s1_awvalid = dut.u_dec.s1_awvalid;
  wire        s1_awready = dut.u_dec.s1_awready;
  wire [31:0] s1_awaddr  = dut.u_dec.s1_awaddr;
  wire        s1_wvalid  = dut.u_dec.s1_wvalid;
  wire        s1_wready  = dut.u_dec.s1_wready;
  wire        s1_wlast   = dut.u_dec.s1_wlast;
  wire        s1_bvalid  = dut.u_dec.s1_bvalid;
  wire        s1_bready  = dut.u_dec.s1_bready;

  wire        conf_busy = dut.u_confreg.busy;
  wire        conf_rw   = dut.u_confreg.R_or_W;
  wire [31:0] conf_simu_flag = dut.u_confreg.simu_flag;
  wire [31:0] conf_rdata_reg = dut.u_confreg.conf_rdata_reg;

  // ---- pipeline handshakes / forwarding debug ----
  wire        ds_valid = dut.u_core.id_stage.ds_valid;
  wire        ds_allowin = dut.u_core.ds_allowin;
  wire        ds_ready_go = dut.u_core.id_stage.ds_ready_go;
  wire        rf2_forward_stall = dut.u_core.id_stage.rf2_forward_stall;
  wire        br_taken = dut.u_core.id_stage.br_taken;
  wire [31:0] rkd_value = dut.u_core.id_stage.rkd_value;

  wire        es_valid = dut.u_core.exe_stage.es_valid;
  wire        es_allowin = dut.u_core.es_allowin;
  wire        es_ready_go = dut.u_core.exe_stage.es_ready_go;

  wire        ms_valid = dut.u_core.mem_stage.ms_valid;
  wire        ms_allowin = dut.u_core.ms_allowin;
  wire        ms_ready_go = dut.u_core.mem_stage.ms_ready_go;
  wire [31:0] ms_dest = dut.u_core.mem_stage.ms_dest;
  wire        ms_load_op = dut.u_core.mem_stage.ms_load_op;
  wire [31:0] ms_final_result = dut.u_core.mem_stage.ms_final_result;

  wire        ws_allowin = dut.u_core.ws_allowin;
  wire        data_data_ok = dut.u_core.data_data_ok;
  wire [31:0] data_rdata   = dut.u_core.data_rdata;
  wire        data_addr_ok = dut.u_core.data_addr_ok;
  wire        data_valid   = dut.u_core.data_valid;

  wire        inst_addr_ok = dut.u_core.if_stage.inst_addr_ok;
  wire        inst_valid   = dut.u_core.if_stage.inst_valid;
  wire        pfs_ready_go = dut.u_core.if_stage.pfs_ready_go;
  wire        fs_allowin   = dut.u_core.if_stage.fs_allowin;
  wire        flush_sign   = dut.u_core.if_stage.flush_sign;
  wire        btb_pre_error_flush = dut.u_core.if_stage.btb_pre_error_flush;
  wire [4:0]  icache_state = dut.u_core.icache.main_state;
  wire [4:0]  dcache_state = dut.u_core.dcache.main_state;
  wire        axi_write_wait = dut.u_core.axi_bridge.write_wait_enable;
  wire        data_rd_req  = dut.u_core.axi_bridge.data_rd_req;
  wire        inst_rd_req  = dut.u_core.axi_bridge.inst_rd_req;
  wire        axi_rd_rdy   = dut.u_core.axi_bridge.data_rd_rdy;

  wire        icache_rd_req = dut.u_core.icache.rd_req;
  wire        icache_rd_req_buffer = dut.u_core.icache.rd_req_buffer;
  wire        icache_icacop_en = dut.u_core.icache.icacop_op_en;
  wire        icache_req_buf_icacop = dut.u_core.icache.request_buffer_icacop;
  wire [1:0]  icache_req_buf_cacop_mode = dut.u_core.icache.request_buffer_cacop_op_mode;
  wire        bridge_rrq_state = dut.u_core.axi_bridge.read_requst_state;
  wire        bridge_rrs_state = dut.u_core.axi_bridge.read_respond_state;
  wire        bridge_arvalid   = dut.u_core.axi_bridge.arvalid;
  wire        bridge_rvalid    = dut.u_core.axi_bridge.rvalid;
  wire        bridge_rlast     = dut.u_core.axi_bridge.rlast;

  wire        ws_excp    = dut.u_core.wb_stage.excp_flush;
  wire [31:0] excp_num   = dut.u_core.wb_stage.ws_excp_num;

  wire [31:0] ds_inst    = dut.u_core.id_stage.ds_inst;
  wire        fetch_btb_target = dut.u_core.if_stage.fetch_btb_target;
  wire [31:0] btb_ret_pc_top   = dut.u_core.btb_ret_pc;
  wire        btb_taken_top    = dut.u_core.btb_taken;
  wire        btb_en_top       = dut.u_core.btb_en;
  wire [31:0] btb_right_target = dut.u_core.id_stage.btb_right_target;
  wire        branch_slot_cancel = dut.u_core.id_stage.branch_slot_cancel;

  wire [1:0]  mem_rstate = dut.u_mem.rstate;
  wire [31:0] mem_r_addr = dut.u_mem.r_addr;
  wire [7:0]  mem_r_cnt  = dut.u_mem.r_cnt;
  wire [31:0] mem_rdata  = dut.u_mem.rdata;
  wire [31:0] s0_araddr  = dut.u_dec.s0_araddr;
  wire        s0_arvalid = dut.u_dec.s0_arvalid;
  wire        s0_arready = dut.u_dec.s0_arready;
  wire        s0_rvalid  = dut.u_dec.s0_rvalid;
  wire        s0_rready  = dut.u_dec.s0_rready;
  wire        s0_rlast   = dut.u_dec.s0_rlast;
  wire [31:0] s0_rdata   = dut.u_dec.s0_rdata;

  // ---- focused cycle trace around shell1 entry ----
  always @(posedge aclk) if (aresetn && cyc >= 10340 && cyc <= 10410) begin
    $display("[T %0d] if=%08x fs=%08x(%b) ds=%08x(%b) es=%08x inst=%08x | br_taken=%b br_flush=%b flush_tg=%08x | btb_taken=%b btb_en=%b btb_ret=%08x fetch_btb=%b right_tg=%08x | r1=%08x r3=%08x r25=%08x r26=%08x cancel=%b",
             cyc, if_nextpc, fs_pc, dut.u_core.if_stage.fs_valid,
             ds_pc, ds_valid, es_pc, ds_inst,
             br_taken, dut.u_core.if_stage.btb_pre_error_flush,
             dut.u_core.id_stage.btb_pre_error_flush_target,
             btb_taken_top, btb_en_top, btb_ret_pc_top, fetch_btb_target,
             btb_right_target,
             dut.u_core.id_stage.u_regfile.rf[1],
             dut.u_core.id_stage.u_regfile.rf[3],
             dut.u_core.id_stage.u_regfile.rf[25],
             dut.u_core.id_stage.u_regfile.rf[26],
             branch_slot_cancel);
    $display("       MEM rstate=%b r_addr=%08x r_cnt=%0d rdata=%08x | s0 AR=%b/%b addr=%08x | R=%b/%b data=%08x last=%b",
             mem_rstate, mem_r_addr, mem_r_cnt, mem_rdata,
             s0_arvalid, s0_arready, s0_araddr,
             s0_rvalid, s0_rready, s0_rdata, s0_rlast);
  end

  // ---- exception stop ----
  always @(posedge aclk) if (aresetn && ws_excp) begin
    $display("[%0d] EXCEPTION ws_pc=%08x excp_num=%08x num=%08x", cyc, ws_pc, excp_num, num_data);
    $display("pipeline: if=%08x fs=%08x ds=%08x es=%08x ms=%08x ws=%08x", if_nextpc, fs_pc, ds_pc, es_pc, ms_pc, ws_pc);
    $display("regs: r12=%08x r13=%08x r14=%08x r15=%08x r1=%08x r3=%08x r25=%08x r26=%08x",
             dut.u_core.id_stage.u_regfile.rf[12],
             dut.u_core.id_stage.u_regfile.rf[13],
             dut.u_core.id_stage.u_regfile.rf[14],
             dut.u_core.id_stage.u_regfile.rf[15],
             dut.u_core.id_stage.u_regfile.rf[1],
             dut.u_core.id_stage.u_regfile.rf[3],
             dut.u_core.id_stage.u_regfile.rf[25],
             dut.u_core.id_stage.u_regfile.rf[26]);
    $finish;
  end

  // ---- register sampling inside bss clear loop ----
  always @(posedge aclk) if (aresetn && ds_pc == 32'h1c0001b4) begin
    $display("[LOOP cyc=%0d] ds_pc=1c0001b4 r12(t0)=%08x r13(t1)=%08x r14(t2)=%08x r15(t3)=%08x",
             cyc,
             dut.u_core.id_stage.u_regfile.rf[12],
             dut.u_core.id_stage.u_regfile.rf[13],
             dut.u_core.id_stage.u_regfile.rf[14],
             dut.u_core.id_stage.u_regfile.rf[15]);
  end

  // ---- event-driven trace around the suspected hang ----
  reg        ev_prev_brrs = 1'b0;
  reg [4:0]  ev_prev_istate = 5'b0;
  reg        ev_prev_icacop_buf = 1'b0;
  reg        ev_prev_icrd_req = 1'b0;
  reg        ev_prev_rrv = 1'b0;
  reg        ev_prev_rrl = 1'b0;
  always @(posedge aclk) if (aresetn) begin
    if (cyc == 0 || bridge_rrs_state != ev_prev_brrs || icache_state != ev_prev_istate ||
         icache_req_buf_icacop != ev_prev_icacop_buf || icache_rd_req != ev_prev_icrd_req ||
         bridge_rvalid != ev_prev_rrv || bridge_rlast != ev_prev_rrl) begin
      $display("[E %0d] PCs=%08x/%08x i$=%b d$=%b icrd=%b icrdbuf=%b icacop_en=%b icacop_buf=%b mode=%b | brrq=%b brrs=%b arv=%b rrv=%b rrl=%b | ird_type=%b ird_addr=%08x",
               cyc, if_nextpc, fs_pc, icache_state, dcache_state,
               icache_rd_req, icache_rd_req_buffer, icache_icacop_en, icache_req_buf_icacop, icache_req_buf_cacop_mode,
               bridge_rrq_state, bridge_rrs_state, bridge_arvalid, bridge_rvalid, bridge_rlast,
               dut.u_core.icache.rd_type, dut.u_core.icache.rd_addr);
      ev_prev_brrs        <= bridge_rrs_state;
      ev_prev_istate      <= icache_state;
      ev_prev_icacop_buf  <= icache_req_buf_icacop;
      ev_prev_icrd_req    <= icache_rd_req;
      ev_prev_rrv         <= bridge_rvalid;
      ev_prev_rrl         <= bridge_rlast;
    end
  end

  // ---- log every confreg read/write transaction ----
  always @(posedge aclk) if (aresetn) begin
    if (s1_arvalid && s1_arready)
      $display("[%0d] CONFREG RD araddr=%08x", cyc, s1_araddr);
    if (s1_rvalid && s1_rready)
      $display("[%0d] CONFREG RD data=%08x last=%b", cyc, s1_rdata, s1_rlast);
    if (s1_awvalid && s1_awready)
      $display("[%0d] CONFREG WR awaddr=%08x", cyc, s1_awaddr);
    if (s1_wvalid && s1_wready)
      $display("[%0d] CONFREG WR data=%08x last=%b", cyc, dut.u_dec.s1_wdata, s1_wlast);
  end

  // ---- one-shot focused window around first observed hang ----
  always @(posedge aclk) if (aresetn && cyc >= 17680 && cyc <= 17750) begin
    $display("[W %0d] if=%08x fs=%08x ds=%08x es=%08x ms=%08x ws=%08x | d$=%b i$=%b | dcache rd_req=%b rd_rdy=%b rd_addr=%08x wr_req=%b | bridge rrq=%b rrs=%b arv=%b/%b addr=%08x id=%h rrv=%b/%b last=%b id=%h data=%08x | mem rstate=%b raddr=%08x rcnt=%0d",
             cyc, if_nextpc, fs_pc, ds_pc, es_pc, ms_pc, ws_pc,
             dcache_state, dut.u_core.icache.main_state,
             dut.u_core.dcache.rd_req, dut.u_core.axi_bridge.data_rd_rdy, dut.u_core.dcache.rd_addr, dut.u_core.dcache.wr_req,
             bridge_rrq_state, bridge_rrs_state, m_arvalid, m_arready, m_araddr, dut.u_core.axi_bridge.arid,
             m_rvalid, m_rready, m_rlast, dut.u_core.axi_bridge.rid, m_rdata,
             mem_rstate, mem_r_addr, mem_r_cnt);
  end

  // ---- stuck-in-write-loop watchdog ----
  reg [31:0] stuck_cyc;
  reg [31:0] stuck_start;
  reg        stuck_print;
  always @(posedge aclk) if (aresetn) begin
    if (es_pc != 32'h1c005fd8) begin
      stuck_cyc  <= 32'd0;
      stuck_print <= 1'b0;
    end else begin
      if (stuck_cyc == 32'd0) stuck_start <= cyc;
      stuck_cyc <= stuck_cyc + 1;
      if (stuck_cyc == 32'd30) stuck_print <= 1'b1;
    end

    if (stuck_print && (stuck_cyc[2:0] == 3'd0)) begin
      $display("[STUCK cyc=%0d delta=%0d] PCs if=%08x fs=%08x ds=%08x es=%08x ms=%08x ws=%08x",
               cyc, cyc - stuck_start, if_nextpc, fs_pc, ds_pc, es_pc, ms_pc, ws_pc);
      $display("  regs r12=%08x r23=%08x r24=%08x r25=%08x r26=%08x",
               dut.u_core.id_stage.u_regfile.rf[12],
               dut.u_core.id_stage.u_regfile.rf[23],
               dut.u_core.id_stage.u_regfile.rf[24],
               dut.u_core.id_stage.u_regfile.rf[25],
               dut.u_core.id_stage.u_regfile.rf[26]);
      $display("  dcache state=%b rd_req=%b rd_addr=%08x wr_req=%b wr_addr=%08x data_ok=%b rdata=%08x",
               dcache_state, data_rd_req, dut.u_core.dcache.rd_addr,
               dut.u_core.dcache.wr_req, dut.u_core.dcache.wr_addr,
               data_data_ok, data_rdata);
      $display("  axi bridge rrq=%b rrs=%b arv=%b rrv=%b rrl=%b | wrq=%b wwait=%b awv=%b wv=%b bv=%b",
               bridge_rrq_state, bridge_rrs_state, bridge_arvalid, bridge_rvalid, bridge_rlast,
               dut.u_core.axi_bridge.write_requst_state, axi_write_wait,
               dut.u_core.axi_bridge.awvalid, dut.u_core.axi_bridge.wvalid, dut.u_core.axi_bridge.bvalid);
      $display("  mem slave rstate=%b raddr=%08x rcnt=%0d | wstate=%b waddr=%08x",
               mem_rstate, mem_r_addr, mem_r_cnt, dut.u_mem.wstate, dut.u_mem.w_addr);
      $display("  dcache rd_req=%b rd_rdy=%b rd_addr=%08x | m AR=%b/%b addr=%08x id=%h | m R=%b/%b last=%b id=%h data=%08x",
               dut.u_core.dcache.rd_req, dut.u_core.axi_bridge.data_rd_rdy, dut.u_core.dcache.rd_addr,
               m_arvalid, m_arready, m_araddr, dut.u_core.axi_bridge.arid,
               m_rvalid, m_rready, m_rlast, dut.u_core.axi_bridge.rid, m_rdata);
      $display("  s0 AR=%b/%b addr=%08x id=%h | s0 R=%b/%b last=%b id=%h data=%08x",
               s0_arvalid, s0_arready, s0_araddr, dut.u_dec.s0_arid,
               s0_rvalid, s0_rready, s0_rlast, dut.u_dec.s0_rid, s0_rdata);
    end

    if (cyc[19:0] == 20'd0) begin
      $display("[H cyc=%0d] if=%08x fs=%08x ds=%08x es=%08x ms=%08x ws=%08x num=%08x",
               cyc, if_nextpc, fs_pc, ds_pc, es_pc, ms_pc, ws_pc, num_data);
      $display("  r12=%08x r13=%08x r23=%08x r24=%08x r25=%08x r26=%08x",
               dut.u_core.id_stage.u_regfile.rf[12],
               dut.u_core.id_stage.u_regfile.rf[13],
               dut.u_core.id_stage.u_regfile.rf[23],
               dut.u_core.id_stage.u_regfile.rf[24],
               dut.u_core.id_stage.u_regfile.rf[25],
               dut.u_core.id_stage.u_regfile.rf[26]);
    end
  end

  initial begin
    repeat (4) @(negedge aclk);
    aresetn = 1;
    for (cyc=0; cyc<25_000; cyc=cyc+1) begin
      @(negedge aclk);
    end
    $display("---- final at cyc=%0d ----", cyc);
    $display("PCs=%08x/%08x/%08x/%08x/%08x/%08x wsV=%b",
             if_nextpc, fs_pc, ds_pc, es_pc, ms_pc, ws_pc, ws_valid);
    $display("num=%08x led=%04x led_rg0=%b led_rg1=%b", num_data, led, led_rg0, led_rg1);
    $display("AXI m: ar=%b/%b addr=%08x | r=%b/%b data=%08x last=%b | aw=%b/%b addr=%08x | w=%b/%b | b=%b/%b",
             m_arvalid, m_arready, m_araddr, m_rvalid, m_rready, m_rdata, m_rlast,
             m_awvalid, m_awready, m_awaddr, m_wvalid, m_wready, m_bvalid, m_bready);
    $display("AXI s1: ar=%b/%b addr=%08x | r=%b/%b data=%08x last=%b | aw=%b/%b | w=%b/%b | b=%b/%b",
             s1_arvalid, s1_arready, s1_araddr, s1_rvalid, s1_rready, s1_rdata, s1_rlast,
             s1_awvalid, s1_awready, s1_wvalid, s1_wready, s1_bvalid, s1_bready);
    $display("conf: busy=%b R_or_W=%b simu_flag=%08x conf_rdata=%08x",
             conf_busy, conf_rw, conf_simu_flag, conf_rdata_reg);
    $finish;
  end
endmodule
