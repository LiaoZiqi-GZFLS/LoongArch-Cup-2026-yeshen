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

    $display("PASS tb_axi_mem_soc");
    $finish;
  end
endmodule
