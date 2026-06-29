`timescale 1ns/1ps
module tb_axi_mem_soc;
  localparam RAMBASE = 32'h1c00_0000;
  localparam SEG     = 32'h1fb0_0000;
  localparam CNT     = 32'h1fb0_0010;
  reg clk=0, reset=1;
  // AR
  reg  [3:0] arid; reg [31:0] araddr; reg [7:0] arlen; reg [2:0] arsize;
  reg  [1:0] arburst; reg arvalid; wire arready;
  // R
  wire [3:0] rid; wire [31:0] rdata; wire [1:0] rresp; wire rlast, rvalid; reg rready;
  // AW
  reg  [3:0] awid; reg [31:0] awaddr; reg [7:0] awlen; reg [2:0] awsize;
  reg  [1:0] awburst; reg awvalid; wire awready;
  // W
  reg  [31:0] wdata; reg [3:0] wstrb; reg wlast, wvalid; wire wready;
  // B
  wire [3:0] bid; wire [1:0] bresp; wire bvalid; reg bready;
  // periph
  wire seg7_we; wire [31:0] seg7_wdata; reg [31:0] cnt_value;

  reg [31:0] seg_captured = 32'hffffffff;
  reg        seg_seen = 1'b0;
  always @(posedge clk) if (seg7_we) begin seg_captured <= seg7_wdata; seg_seen <= 1'b1; end

  axi_mem_soc #(.INIT_FILE("")) dut(
    .clk(clk),.reset(reset),
    .arid(arid),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),.arvalid(arvalid),.arready(arready),
    .rid(rid),.rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
    .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
    .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
    .bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready),
    .seg7_we(seg7_we),.seg7_wdata(seg7_wdata),.cnt_value(cnt_value));

  always #5 clk = ~clk;

  // single-beat write task (len=0, word)
  task axi_write1(input [31:0] a, input [31:0] d);
  begin
    @(negedge clk); awid=4'h1; awaddr=a; awlen=0; awsize=3'd2; awburst=2'b01; awvalid=1;
                    wdata=d; wstrb=4'hf; wlast=1; wvalid=1; bready=1;
    wait(awready); @(negedge clk); awvalid=0;
    wait(wready);  @(negedge clk); wvalid=0; wlast=0;
    wait(bvalid);  @(negedge clk); bready=0;
  end endtask

  // single-beat read task (len=0, word); returns dut rdata via global
  reg [31:0] rd_result;
  task axi_read1(input [31:0] a);
  begin
    @(negedge clk); arid=4'h1; araddr=a; arlen=0; arsize=3'd2; arburst=2'b01; arvalid=1; rready=1;
    wait(arready); @(negedge clk); arvalid=0;
    wait(rvalid);  rd_result=rdata; @(negedge clk); rready=0;
  end endtask

  initial begin
    arvalid=0; awvalid=0; wvalid=0; rready=0; bready=0; cnt_value=32'h1234_5678;
    @(negedge clk); reset=0;
    // RAM write then read back
    axi_write1(RAMBASE+32'h20, 32'hCAFEF00D);
    axi_read1 (RAMBASE+32'h20);
    if (rd_result!==32'hCAFEF00D) begin $display("FAIL ram rw got %h",rd_result); $finish; end
    // MMIO: write seg7
    axi_write1(SEG, 32'h00000037);
    @(negedge clk); @(negedge clk);
    if (!seg_seen || seg_captured!==32'h00000037) begin
      $display("FAIL seg7 write not observed: seen=%b data=%h", seg_seen, seg_captured); $finish; end
    // MMIO: read counter
    axi_read1(CNT);
    if (rd_result!==32'h1234_5678) begin $display("FAIL cnt read got %h",rd_result); $finish; end

    // burst write 4 beats (cache line) then burst read back
    @(negedge clk); awid=4'h1; awaddr=RAMBASE+32'h40; awlen=8'd3; awsize=3'd2; awburst=2'b01; awvalid=1; bready=1;
    wait(awready); @(negedge clk); awvalid=0;
    wdata=32'h11111111; wstrb=4'hf; wlast=0; wvalid=1; wait(wready); @(negedge clk);
    wdata=32'h22222222; wait(wready); @(negedge clk);
    wdata=32'h33333333; wait(wready); @(negedge clk);
    wdata=32'h44444444; wlast=1;     wait(wready); @(negedge clk); wvalid=0; wlast=0;
    wait(bvalid); @(negedge clk); bready=0;
    axi_read1(RAMBASE+32'h48);   // 3rd word
    if (rd_result!==32'h33333333) begin $display("FAIL burst got %h",rd_result); $finish; end

    // burst read 4 beats from RAMBASE+0x40, verify data + rlast on last beat only
    begin : burst_rd
      integer bi; reg [31:0] exp [0:3];
      exp[0]=32'h11111111; exp[1]=32'h22222222; exp[2]=32'h33333333; exp[3]=32'h44444444;
      @(negedge clk); arid=4'h2; araddr=RAMBASE+32'h40; arlen=8'd3; arsize=3'd2; arburst=2'b01; arvalid=1; rready=1;
      wait(arready); @(negedge clk); arvalid=0;
      for (bi=0; bi<4; bi=bi+1) begin
        wait(rvalid);
        if (rdata!==exp[bi]) begin $display("FAIL burst-rd beat %0d got %h want %h", bi, rdata, exp[bi]); $finish; end
        if (rlast !== (bi==3)) begin $display("FAIL burst-rd rlast beat %0d rlast=%b", bi, rlast); $finish; end
        if (rid !== 4'h2)     begin $display("FAIL burst-rd rid=%h (want 2)", rid); $finish; end
        @(negedge clk);
      end
      rready=0;
    end

    // partial wstrb: only byte 0 should update
    axi_write1(RAMBASE+32'h80, 32'hAABBCCDD);
    @(negedge clk); awid=4'h1; awaddr=RAMBASE+32'h80; awlen=0; awsize=3'd2; awburst=2'b01; awvalid=1;
                    wdata=32'h00000011; wstrb=4'h1; wlast=1; wvalid=1; bready=1;
    wait(awready); @(negedge clk); awvalid=0;
    wait(wready);  @(negedge clk); wvalid=0; wlast=0;
    wait(bvalid);  @(negedge clk); bready=0;
    axi_read1(RAMBASE+32'h80);
    if (rd_result!==32'hAABBCC11) begin $display("FAIL wstrb got %h want AABBCC11", rd_result); $finish; end

    $display("PASS tb_axi_mem_soc");
    $finish;
  end
endmodule
