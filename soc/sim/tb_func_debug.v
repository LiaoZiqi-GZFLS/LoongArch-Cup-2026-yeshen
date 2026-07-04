`timescale 1ns/1ps
// Minimal debug testbench: run the functional binary and, when num_data has been
// stable for a long time, dump the pipeline PCs and AXI/confreg status.
module tb_func_debug;
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

  initial begin
    $dumpfile("build/tb_func_debug.vcd"); $dumpvars(0, tb_func_debug);
    repeat (4) @(negedge aclk);
    aresetn = 1;
    for (cyc=0; cyc<7_000_000; cyc=cyc+1) begin
      @(negedge aclk);
      if (num_data !== 32'h0 && num_stable >= 100_000) begin
        $display("program reached steady state at cyc=%0d", cyc);
        $display("final num_data=0x%08x led=%04x led_rg0=%b led_rg1=%b", num_data, led, led_rg0, led_rg1);
        $display("final IF/nextpc=%08x fs=%08x ds=%08x es=%08x ms=%08x ws=%08x ws_valid=%b",
                 if_nextpc, fs_pc, ds_pc, es_pc, ms_pc, ws_pc, ws_valid);
        $display("AXI: ar=%b/%b addr=%08x | r=%b/%b last=%b | aw=%b/%b addr=%08x | w=%b/%b | b=%b/%b",
                 m_arvalid, m_arready, m_araddr, m_rvalid, m_rready, m_rlast,
                 m_awvalid, m_awready, m_awaddr, m_wvalid, m_wready, m_bvalid, m_bready);
        if (num_data === 32'h003a003a && led_rg0 === 2'b01 && led_rg1 === 2'b01)
          $display("PASS tb_func_debug");
        else
          $display("FAIL tb_func_debug");
        $finish;
      end
    end
    $display("WARN: hit 7M-cycle cap");
    $display("final num_data=0x%08x", num_data);
    $display("final IF/nextpc=%08x fs=%08x ds=%08x es=%08x ms=%08x ws=%08x ws_valid=%b",
             if_nextpc, fs_pc, ds_pc, es_pc, ms_pc, ws_pc, ws_valid);
    $display("AXI: ar=%b/%b addr=%08x | r=%b/%b last=%b | aw=%b/%b addr=%08x | w=%b/%b | b=%b/%b",
             m_arvalid, m_arready, m_araddr, m_rvalid, m_rready, m_rlast,
             m_awvalid, m_awready, m_awaddr, m_wvalid, m_wready, m_bvalid, m_bready);
    $finish;
  end
endmodule
