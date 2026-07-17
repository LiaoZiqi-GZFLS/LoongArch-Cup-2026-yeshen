`timescale 1ns/1ps
// SoC top: openLA500 core (AXI3 master, DA mode) +
//   AXI 1x2 decoder +
//   axi_mem_soc (1 MB BRAM + demo MMIO at 0x1fb0_xxxx) +
//   ChipLab nscscc-team confreg (0xbfaf_xxxx).
//
// The confreg module drives the board's 7-segment display / LEDs and provides the
// control/status registers the official functional/performance test programs expect.
// The old seg7/counter demo peripherals are kept at 0x1fb0_0000/0x1fb0_0010.
module soc_top #(
    parameter INIT_FILE = ""
)(
    input             aclk,
    input             aresetn,
    output     [31:0] seg_disp,    // old demo seg7 value (0x1fb0_0000)
    output     [31:0] cnt_value,   // old demo cycle counter value (0x1fb0_0010)

    // ChipLab confreg board outputs
    output     [15:0] led,
    output     [ 1:0] led_rg0,
    output     [ 1:0] led_rg1,
    output     [ 7:0] num_csn,
    output     [ 6:0] num_a_g,
    output     [31:0] num_data,

    // ChipLab confreg board inputs
    input      [ 7:0] switch,
    input      [ 3:0] btn_key_row,
    input      [ 1:0] btn_step
);
    // AXI3 master wires from the core
    wire [ 3:0] arid;  wire [31:0] araddr; wire [7:0] arlen; wire [2:0] arsize;
    wire [ 1:0] arburst, arlock; wire [3:0] arcache; wire [2:0] arprot; wire arvalid, arready;
    wire [ 3:0] rid;   wire [31:0] rdata;  wire [1:0] rresp; wire rlast, rvalid, rready;
    wire [ 3:0] awid;  wire [31:0] awaddr; wire [7:0] awlen; wire [2:0] awsize;
    wire [ 1:0] awburst, awlock; wire [3:0] awcache; wire [2:0] awprot; wire awvalid, awready;
    wire [31:0] wdata;  wire [3:0] wstrb; wire wlast, wvalid, wready;
    wire [ 3:0] bid;   wire [1:0] bresp;   wire bvalid, bready;

    // slave 0 (BRAM/MMIO)
    wire [ 3:0] s0_arid;  wire [31:0] s0_araddr; wire [7:0] s0_arlen; wire [2:0] s0_arsize;
    wire [ 1:0] s0_arburst; wire s0_arvalid, s0_arready;
    wire [ 3:0] s0_rid;   wire [31:0] s0_rdata;  wire [1:0] s0_rresp; wire s0_rlast, s0_rvalid, s0_rready;
    wire [ 3:0] s0_awid;  wire [31:0] s0_awaddr; wire [7:0] s0_awlen; wire [2:0] s0_awsize;
    wire [ 1:0] s0_awburst; wire s0_awvalid, s0_awready;
    wire [31:0] s0_wdata;  wire [3:0] s0_wstrb; wire s0_wlast, s0_wvalid, s0_wready;
    wire [ 3:0] s0_bid;   wire [1:0] s0_bresp; wire s0_bvalid, s0_bready;

    // slave 1 (confreg)
    wire [ 3:0] s1_arid;  wire [31:0] s1_araddr; wire [7:0] s1_arlen; wire [2:0] s1_arsize;
    wire [ 1:0] s1_arburst; wire s1_arvalid, s1_arready;
    wire [ 3:0] s1_rid;   wire [31:0] s1_rdata;  wire [1:0] s1_rresp; wire s1_rlast, s1_rvalid, s1_rready;
    wire [ 3:0] s1_awid;  wire [31:0] s1_awaddr; wire [7:0] s1_awlen; wire [2:0] s1_awsize;
    wire [ 1:0] s1_awburst; wire s1_awvalid, s1_awready;
    wire [31:0] s1_wdata;  wire [3:0] s1_wstrb; wire s1_wlast, s1_wvalid, s1_wready;
    wire [ 3:0] s1_bid;   wire [1:0] s1_bresp; wire s1_bvalid, s1_bready;

    wire        seg7_we;
    wire [31:0] seg7_wdata;

    core_top u_core(
        .aclk(aclk), .aresetn(aresetn), .intrpt(8'b0),
        .arid(arid),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),
        .arlock(arlock),.arcache(arcache),.arprot(arprot),.arvalid(arvalid),.arready(arready),
        .rid(rid),.rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),
        .awlock(awlock),.awcache(awcache),.awprot(awprot),.awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
        .bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready),
        .break_point(1'b0),.infor_flag(1'b0),.reg_num(5'b0),
        .ws_valid(),.rf_rdata(),
        .debug0_wb_pc(),.debug0_wb_rf_wen(),.debug0_wb_rf_wnum(),
        .debug0_wb_rf_wdata(),.debug0_wb_inst()
    );

    axi_decoder_1x2 u_dec(
        .aclk(aclk), .aresetn(aresetn),
        .m_arid(arid),.m_araddr(araddr),.m_arlen(arlen),.m_arsize(arsize),.m_arburst(arburst),
        .m_arvalid(arvalid),.m_arready(arready),
        .m_rid(rid),.m_rdata(rdata),.m_rresp(rresp),.m_rlast(rlast),.m_rvalid(rvalid),.m_rready(rready),
        .m_awid(awid),.m_awaddr(awaddr),.m_awlen(awlen),.m_awsize(awsize),.m_awburst(awburst),
        .m_awvalid(awvalid),.m_awready(awready),
        .m_wdata(wdata),.m_wstrb(wstrb),.m_wlast(wlast),.m_wvalid(wvalid),.m_wready(wready),
        .m_bid(bid),.m_bresp(bresp),.m_bvalid(bvalid),.m_bready(bready),

        .s0_arid(s0_arid),.s0_araddr(s0_araddr),.s0_arlen(s0_arlen),.s0_arsize(s0_arsize),.s0_arburst(s0_arburst),
        .s0_arvalid(s0_arvalid),.s0_arready(s0_arready),
        .s0_rid(s0_rid),.s0_rdata(s0_rdata),.s0_rresp(s0_rresp),.s0_rlast(s0_rlast),.s0_rvalid(s0_rvalid),.s0_rready(s0_rready),
        .s0_awid(s0_awid),.s0_awaddr(s0_awaddr),.s0_awlen(s0_awlen),.s0_awsize(s0_awsize),.s0_awburst(s0_awburst),
        .s0_awvalid(s0_awvalid),.s0_awready(s0_awready),
        .s0_wdata(s0_wdata),.s0_wstrb(s0_wstrb),.s0_wlast(s0_wlast),.s0_wvalid(s0_wvalid),.s0_wready(s0_wready),
        .s0_bid(s0_bid),.s0_bresp(s0_bresp),.s0_bvalid(s0_bvalid),.s0_bready(s0_bready),

        .s1_arid(s1_arid),.s1_araddr(s1_araddr),.s1_arlen(s1_arlen),.s1_arsize(s1_arsize),.s1_arburst(s1_arburst),
        .s1_arvalid(s1_arvalid),.s1_arready(s1_arready),
        .s1_rid(s1_rid),.s1_rdata(s1_rdata),.s1_rresp(s1_rresp),.s1_rlast(s1_rlast),.s1_rvalid(s1_rvalid),.s1_rready(s1_rready),
        .s1_awid(s1_awid),.s1_awaddr(s1_awaddr),.s1_awlen(s1_awlen),.s1_awsize(s1_awsize),.s1_awburst(s1_awburst),
        .s1_awvalid(s1_awvalid),.s1_awready(s1_awready),
        .s1_wdata(s1_wdata),.s1_wstrb(s1_wstrb),.s1_wlast(s1_wlast),.s1_wvalid(s1_wvalid),.s1_wready(s1_wready),
        .s1_bid(s1_bid),.s1_bresp(s1_bresp),.s1_bvalid(s1_bvalid),.s1_bready(s1_bready)
    );

    axi_mem_soc #(.INIT_FILE(INIT_FILE)) u_mem(
        .clk(aclk), .reset(~aresetn),
        .arid(s0_arid),.araddr(s0_araddr),.arlen(s0_arlen),.arsize(s0_arsize),.arburst(s0_arburst),
        .arvalid(s0_arvalid),.arready(s0_arready),
        .rid(s0_rid),.rdata(s0_rdata),.rresp(s0_rresp),.rlast(s0_rlast),.rvalid(s0_rvalid),.rready(s0_rready),
        .awid(s0_awid),.awaddr(s0_awaddr),.awlen(s0_awlen),.awsize(s0_awsize),.awburst(s0_awburst),
        .awvalid(s0_awvalid),.awready(s0_awready),
        .wdata(s0_wdata),.wstrb(s0_wstrb),.wlast(s0_wlast),.wvalid(s0_wvalid),.wready(s0_wready),
        .bid(s0_bid),.bresp(s0_bresp),.bvalid(s0_bvalid),.bready(s0_bready),
        .seg7_we(seg7_we),.seg7_wdata(seg7_wdata),.cnt_value(cnt_value)
    );

    confreg #(.SIMULATION(1'b1)) u_confreg(
        .aclk(aclk),
        .timer_clk(aclk),
        .aresetn(aresetn),
        .sys_resetn(aresetn),
        .arid(s1_arid),.araddr(s1_araddr),.arlen(s1_arlen),.arsize(s1_arsize),.arburst(s1_arburst),
        .arlock(arlock),.arcache(arcache),.arprot(arprot),
        .arvalid(s1_arvalid),.arready(s1_arready),
        .rid(s1_rid),.rdata(s1_rdata),.rresp(s1_rresp),.rlast(s1_rlast),.rvalid(s1_rvalid),.rready(s1_rready),
        .awid(s1_awid),.awaddr(s1_awaddr),.awlen(s1_awlen),.awsize(s1_awsize),.awburst(s1_awburst),
        .awlock(awlock),.awcache(awcache),.awprot(awprot),
        .awvalid(s1_awvalid),.awready(s1_awready),
        .wdata(s1_wdata),.wstrb(s1_wstrb),.wlast(s1_wlast),.wvalid(s1_wvalid),.wready(s1_wready),
        .bid(s1_bid),.bresp(s1_bresp),.bvalid(s1_bvalid),.bready(s1_bready),
        .ram_random_mask(),
        .led(led),
        .led_rg0(led_rg0),
        .led_rg1(led_rg1),
        .num_csn(num_csn),
        .num_a_g(num_a_g),
        .num_data(num_data),
        .switch(switch),
        .btn_key_col(),
        .btn_key_row(btn_key_row),
        .btn_step(btn_step)
    );

    counter u_cnt(.clk(aclk), .reset(~aresetn), .cycle_cnt(cnt_value));
    seg7    u_seg(.clk(aclk), .reset(~aresetn), .we(seg7_we), .wdata(seg7_wdata), .disp(seg_disp));
endmodule
