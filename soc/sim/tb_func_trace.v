`timescale 1ns/1ps
// Trace testbench for debugging the functional-test hang.
// Identical to tb_func but logs pipeline PCs and AXI handshakes to
// build/func_trace.log so we can see exactly where execution stalls.
module tb_func_trace;
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

  // ---- trace log file ----
  integer log;
  initial begin
    log = $fopen("build/func_trace.log");
    if (log == 0) $display("ERROR: could not open build/func_trace.log");
  end

  // ---- hierarchical probes ----
  // These names match the instance names in soc_top.v / mycpu_top.v.
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
  wire        s1_rvalid  = dut.u_dec.s1_rvalid;
  wire        s1_rready  = dut.u_dec.s1_rready;
  wire        s1_awvalid = dut.u_dec.s1_awvalid;
  wire        s1_awready = dut.u_dec.s1_awready;
  wire        s1_wvalid  = dut.u_dec.s1_wvalid;
  wire        s1_wready  = dut.u_dec.s1_wready;
  wire        s1_bvalid  = dut.u_dec.s1_bvalid;
  wire        s1_bready  = dut.u_dec.s1_bready;

  wire        conf_busy = dut.u_confreg.busy;
  wire        conf_rw   = dut.u_confreg.R_or_W;

  // ---- periodic trace sample ----
  localparam SAMPLE_EVERY = 1000;
  localparam SAMPLE_DEPTH = 64;
  reg [31:0] sample_cyc  [0:SAMPLE_DEPTH-1];
  reg [31:0] sample_ifpc [0:SAMPLE_DEPTH-1];
  reg [31:0] sample_fspc [0:SAMPLE_DEPTH-1];
  reg [31:0] sample_dspc [0:SAMPLE_DEPTH-1];
  reg [31:0] sample_espc [0:SAMPLE_DEPTH-1];
  reg [31:0] sample_mspc [0:SAMPLE_DEPTH-1];
  reg [31:0] sample_wspc [0:SAMPLE_DEPTH-1];
  reg [31:0] sample_num  [0:SAMPLE_DEPTH-1];
  reg [15:0] sample_ar   [0:SAMPLE_DEPTH-1]; // {arvalid,arready,m_araddr[13:0]}
  reg [15:0] sample_r    [0:SAMPLE_DEPTH-1]; // {rvalid,rready,rlast,rsel?}
  integer sample_idx = 0;

  task write_sample_header;
    begin
      $fwrite(log, "cyc      num_data   IF/nextpc  fs_pc      ds_pc      es_pc      ms_pc      ws_pc      V AR[va rdy addr]    R[v rdy last]\n");
    end
  endtask

  task write_sample_line(input integer c, input [31:0] nd,
                         input [31:0] ifpc, input [31:0] fpc, input [31:0] dpc,
                         input [31:0] epc,  input [31:0] mpc, input [31:0] wpc,
                         input [31:0] arinfo, input [31:0] rinfo);
    begin
      $fwrite(log, "%8d %08x %08x %08x %08x %08x %08x %08x %b %b%b %04x    %b%b%b\n",
              c, nd, ifpc, fpc, dpc, epc, mpc, wpc, ws_valid,
              arinfo[31], arinfo[30], arinfo[13:0],
              rinfo[2], rinfo[1], rinfo[0]);
    end
  endtask

  initial write_sample_header;

  always @(posedge aclk) if (aresetn) begin
    // log every write-back commit to a file for post-mortem instruction trace
    if (ws_valid)
      $fwrite(log, "[%8d] COMMIT pc=%08x inst=%08x wen=%b wn=%02d wd=%08x\n",
              cyc, ws_pc, dut.u_core.debug0_wb_inst,
              dut.u_core.debug0_wb_rf_wen, dut.u_core.debug0_wb_rf_wnum,
              dut.u_core.debug0_wb_rf_wdata);

    // periodic sample into circular buffer
    if (cyc % SAMPLE_EVERY == 0) begin
      sample_cyc [sample_idx] <= cyc;
      sample_num [sample_idx] <= num_data;
      sample_ifpc[sample_idx] <= if_nextpc;
      sample_fspc[sample_idx] <= fs_pc;
      sample_dspc[sample_idx] <= ds_pc;
      sample_espc[sample_idx] <= es_pc;
      sample_mspc[sample_idx] <= ms_pc;
      sample_wspc[sample_idx] <= ws_pc;
      sample_ar  [sample_idx] <= {m_arvalid, m_arready, m_araddr[13:0]};
      sample_r   [sample_idx] <= {m_rvalid, m_rready, m_rlast};
      sample_idx <= (sample_idx == SAMPLE_DEPTH-1) ? 0 : sample_idx + 1;
    end
  end

  // ---- num_data change detection + final checks ----
  reg [31:0] num_prev = 32'h0;
  reg [31:0] num_stable = 32'd0;

  always @(posedge aclk) if (aresetn) begin
    if (num_data !== num_prev) begin
      $display("[%0t] num_data <= 0x%08x  led=%04x led_rg0=%b led_rg1=%b  IF=%08x fs=%08x ds=%08x es=%08x ms=%08x ws=%08x",
               $time, num_data, led, led_rg0, led_rg1,
               if_nextpc, fs_pc, ds_pc, es_pc, ms_pc, ws_pc);
      num_prev   <= num_data;
      num_stable <= 32'd0;
    end else begin
      num_stable <= num_stable + 1;
    end
  end

  task dump_samples;
    integer i, idx;
    begin
      $fwrite(log, "\n--- last %0d periodic samples (oldest first) ---\n", SAMPLE_DEPTH);
      $fwrite(log, "cyc      num_data   IF/nextpc  fs_pc      ds_pc      es_pc      ms_pc      ws_pc      V AR[va rdy addr]    R[v rdy last]\n");
      for (i=0; i<SAMPLE_DEPTH; i=i+1) begin
        idx = (sample_idx + i) % SAMPLE_DEPTH;
        $fwrite(log, "%8d %08x %08x %08x %08x %08x %08x %08x %b %b%b %04x    %b%b%b\n",
                sample_cyc[idx], sample_num[idx],
                sample_ifpc[idx], sample_fspc[idx], sample_dspc[idx],
                sample_espc[idx], sample_mspc[idx], sample_wspc[idx],
                sample_wspc[idx] != 32'b0, // proxy for ws_valid not stored
                sample_ar[idx][15], sample_ar[idx][14], sample_ar[idx][13:0],
                sample_r[idx][2], sample_r[idx][1], sample_r[idx][0]);
      end
    end
  endtask

  task do_final_checks;
    begin
      dump_samples;
      $display("\nfinal num_data=0x%08x led=%04x led_rg0=%b led_rg1=%b", num_data, led, led_rg0, led_rg1);
      $display("final IF/nextpc=%08x fs=%08x ds=%08x es=%08x ms=%08x ws=%08x ws_valid=%b",
               if_nextpc, fs_pc, ds_pc, es_pc, ms_pc, ws_pc, ws_valid);
      $display("AXI: ar=%b/%b addr=%08x | r=%b/%b last=%b | aw=%b/%b | w=%b/%b | b=%b/%b",
               m_arvalid, m_arready, m_araddr, m_rvalid, m_rready, m_rlast,
               m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready);
      $display("confreg: s1_ar=%b/%b s1_r=%b/%b s1_aw=%b/%b s1_w=%b/%b s1_b=%b/%b busy=%b R_or_W=%b",
               s1_arvalid, s1_arready, s1_rvalid, s1_rready,
               s1_awvalid, s1_awready, s1_wvalid, s1_wready,
               s1_bvalid, s1_bready, conf_busy, conf_rw);
      if (num_data === 32'h3a00003a && led_rg0 === 2'b01 && led_rg1 === 2'b01)
        $display("PASS tb_func_trace: functional test passed");
      else
        $display("FAIL tb_func_trace: expected 0x3a00003a/green/green");
      $fclose(log);
      $finish;
    end
  endtask

  initial begin
    $dumpfile("build/tb_func_trace.vcd"); $dumpvars(0, tb_func_trace);
    repeat (4) @(negedge aclk);
    aresetn = 1;
    for (cyc=0; cyc<6_000_000; cyc=cyc+1) begin
      @(negedge aclk);
      if (num_data !== 32'h0 && num_stable >= 100_000) begin
        $display("program reached steady state (num_data stable %0d cycles) at cyc=%0d", num_stable, cyc);
        do_final_checks;
      end
    end
    $display("WARN: hit 50M-cycle safety cap");
    do_final_checks;
  end
endmodule
