`timescale 1ns/1ps
// Minimal SoC top: openLA500 core (AXI3 master, DA mode) + AXI BRAM/MMIO slave + counter + seg7.
// The CPU core (core_top, soc/rtl/core/) is derived from the third-party openLA500 (齐物)
// LA32R core — see soc/NOTICE for attribution. The contest design report must also cite it.
module soc_top #(
    parameter INIT_FILE = ""
)(
    input             aclk,
    input             aresetn,
    output     [31:0] seg_disp,    // observable seven-seg value
    output     [31:0] cnt_value    // observable cycle counter
);
    // AXI3 wires between core master and slave
    wire [ 3:0] arid;  wire [31:0] araddr; wire [7:0] arlen; wire [2:0] arsize;
    wire [ 1:0] arburst, arlock; wire [3:0] arcache; wire [2:0] arprot; wire arvalid, arready;
    wire [ 3:0] rid;   wire [31:0] rdata;  wire [1:0] rresp; wire rlast, rvalid, rready;
    wire [ 3:0] awid;  wire [31:0] awaddr; wire [7:0] awlen; wire [2:0] awsize;
    wire [ 1:0] awburst, awlock; wire [3:0] awcache; wire [2:0] awprot; wire awvalid, awready;
    wire [ 3:0] wid;   wire [31:0] wdata;  wire [3:0] wstrb; wire wlast, wvalid, wready;
    wire [ 3:0] bid;   wire [1:0] bresp;   wire bvalid, bready;

    // Note: core drives arlock/arcache/arprot/awlock/awcache/awprot/wid, but the
    // BRAM/MMIO slave ignores them (single master, no cache coherency / protection),
    // so those nets terminate at the core instance below and are intentionally unused.

    wire        seg7_we;     // MMIO seg7 write pulse from slave
    wire [31:0] seg7_wdata;  // MMIO seg7 write data from slave

    core_top u_core(
        .aclk(aclk), .aresetn(aresetn), .intrpt(8'b0),
        .arid(arid),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),
        .arlock(arlock),.arcache(arcache),.arprot(arprot),.arvalid(arvalid),.arready(arready),
        .rid(rid),.rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),
        .awlock(awlock),.awcache(awcache),.awprot(awprot),.awvalid(awvalid),.awready(awready),
        .wid(wid),.wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
        .bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready),
        .break_point(1'b0),.infor_flag(1'b0),.reg_num(5'b0),
        .ws_valid(),.rf_rdata(),
        .debug0_wb_pc(),.debug0_wb_rf_wen(),.debug0_wb_rf_wnum(),
        .debug0_wb_rf_wdata(),.debug0_wb_inst()
    );

    axi_mem_soc #(.INIT_FILE(INIT_FILE)) u_mem(
        .clk(aclk), .reset(~aresetn),
        .arid(arid),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),
        .arvalid(arvalid),.arready(arready),
        .rid(rid),.rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),
        .awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
        .bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready),
        .seg7_we(seg7_we),.seg7_wdata(seg7_wdata),.cnt_value(cnt_value)
    );

    counter u_cnt(.clk(aclk), .reset(~aresetn), .cycle_cnt(cnt_value));
    seg7    u_seg(.clk(aclk), .reset(~aresetn), .we(seg7_we), .wdata(seg7_wdata), .disp(seg_disp));
endmodule
