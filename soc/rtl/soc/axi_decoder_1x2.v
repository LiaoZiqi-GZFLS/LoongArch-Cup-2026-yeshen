`timescale 1ns/1ps
// Simple AXI3 1-master -> 2-slave address decoder for the ChipLab SoC.
// Slave 0 (mem): everything except 0xbfaf_xxxx.
// Slave 1 (confreg): addresses whose upper 16 bits are 0xbfaf (the kseg1
// uncached window the official functional/performance tests use).
//
// Only AR/AW/R/W/B are routed; lock/cache/prot/wid sidebands are ignored by
// both slaves and are left unconnected on the master side in soc_top.
// The core is a single AXI master, so the decoder simply captures the target
// during the AR/AW handshake and steers the rest of the burst accordingly.
module axi_decoder_1x2 #(
    parameter CONF_HI = 16'hbfaf
)(
    input             aclk,
    input             aresetn,

    // master (core)
    input      [ 3:0] m_arid,
    input      [31:0] m_araddr,
    input      [ 7:0] m_arlen,
    input      [ 2:0] m_arsize,
    input      [ 1:0] m_arburst,
    input             m_arvalid,
    output            m_arready,

    output     [ 3:0] m_rid,
    output     [31:0] m_rdata,
    output     [ 1:0] m_rresp,
    output            m_rlast,
    output            m_rvalid,
    input             m_rready,

    input      [ 3:0] m_awid,
    input      [31:0] m_awaddr,
    input      [ 7:0] m_awlen,
    input      [ 2:0] m_awsize,
    input      [ 1:0] m_awburst,
    input             m_awvalid,
    output            m_awready,

    input      [31:0] m_wdata,
    input      [ 3:0] m_wstrb,
    input             m_wlast,
    input             m_wvalid,
    output            m_wready,

    output     [ 3:0] m_bid,
    output     [ 1:0] m_bresp,
    output            m_bvalid,
    input             m_bready,

    // slave 0 (axi_mem_soc: BRAM + demo MMIO)
    output reg [ 3:0] s0_arid,
    output reg [31:0] s0_araddr,
    output reg [ 7:0] s0_arlen,
    output reg [ 2:0] s0_arsize,
    output reg [ 1:0] s0_arburst,
    output reg        s0_arvalid,
    input             s0_arready,

    input      [ 3:0] s0_rid,
    input      [31:0] s0_rdata,
    input      [ 1:0] s0_rresp,
    input             s0_rlast,
    input             s0_rvalid,
    output reg        s0_rready,

    output reg [ 3:0] s0_awid,
    output reg [31:0] s0_awaddr,
    output reg [ 7:0] s0_awlen,
    output reg [ 2:0] s0_awsize,
    output reg [ 1:0] s0_awburst,
    output reg        s0_awvalid,
    input             s0_awready,

    output reg [31:0] s0_wdata,
    output reg [ 3:0] s0_wstrb,
    output reg        s0_wlast,
    output reg        s0_wvalid,
    input             s0_wready,

    input      [ 3:0] s0_bid,
    input      [ 1:0] s0_bresp,
    input             s0_bvalid,
    output reg        s0_bready,

    // slave 1 (confreg)
    output reg [ 3:0] s1_arid,
    output reg [31:0] s1_araddr,
    output reg [ 7:0] s1_arlen,
    output reg [ 2:0] s1_arsize,
    output reg [ 1:0] s1_arburst,
    output reg        s1_arvalid,
    input             s1_arready,

    input      [ 3:0] s1_rid,
    input      [31:0] s1_rdata,
    input      [ 1:0] s1_rresp,
    input             s1_rlast,
    input             s1_rvalid,
    output reg        s1_rready,

    output reg [ 3:0] s1_awid,
    output reg [31:0] s1_awaddr,
    output reg [ 7:0] s1_awlen,
    output reg [ 2:0] s1_awsize,
    output reg [ 1:0] s1_awburst,
    output reg        s1_awvalid,
    input             s1_awready,

    output reg [31:0] s1_wdata,
    output reg [ 3:0] s1_wstrb,
    output reg        s1_wlast,
    output reg        s1_wvalid,
    input             s1_wready,

    input      [ 3:0] s1_bid,
    input      [ 1:0] s1_bresp,
    input             s1_bvalid,
    output reg        s1_bready
);

    wire sel_ar_conf = (m_araddr[31:16] == CONF_HI);
    wire sel_aw_conf = (m_awaddr[31:16] == CONF_HI);

    reg rsel_conf;
    reg wsel_conf;

    // Track in-progress read/write bursts so a new AR/AW handshake cannot
    // change rsel_conf/wsel_conf while R/W beats are still being routed.
    reg r_busy;
    reg w_busy;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) r_busy <= 1'b0;
        else if (m_arvalid && m_arready) r_busy <= 1'b1;
        else if (m_rvalid && m_rready && m_rlast) r_busy <= 1'b0;
    end

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) w_busy <= 1'b0;
        else if (m_awvalid && m_awready) w_busy <= 1'b1;
        else if (m_bvalid && m_bready) w_busy <= 1'b0;
    end

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) rsel_conf <= 1'b0;
        else if (m_arvalid && m_arready) rsel_conf <= sel_ar_conf;
    end

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) wsel_conf <= 1'b0;
        else if (m_awvalid && m_awready) wsel_conf <= sel_aw_conf;
    end

    // AR routing
    always @(*) begin
        s0_arid    = m_arid;
        s0_araddr  = m_araddr;
        s0_arlen   = m_arlen;
        s0_arsize  = m_arsize;
        s0_arburst = m_arburst;
        s0_arvalid = m_arvalid && !sel_ar_conf && !r_busy;

        s1_arid    = m_arid;
        s1_araddr  = m_araddr;
        s1_arlen   = m_arlen;
        s1_arsize  = m_arsize;
        s1_arburst = m_arburst;
        s1_arvalid = m_arvalid &&  sel_ar_conf && !r_busy;
    end
    assign m_arready = !r_busy && (sel_ar_conf ? s1_arready : s0_arready);

    // AW routing
    always @(*) begin
        s0_awid    = m_awid;
        s0_awaddr  = m_awaddr;
        s0_awlen   = m_awlen;
        s0_awsize  = m_awsize;
        s0_awburst = m_awburst;
        s0_awvalid = m_awvalid && !sel_aw_conf && !w_busy;

        s1_awid    = m_awid;
        s1_awaddr  = m_awaddr;
        s1_awlen   = m_awlen;
        s1_awsize  = m_awsize;
        s1_awburst = m_awburst;
        s1_awvalid = m_awvalid &&  sel_aw_conf && !w_busy;
    end
    assign m_awready = !w_busy && (sel_aw_conf ? s1_awready : s0_awready);

    // W routing
    always @(*) begin
        s0_wdata  = m_wdata;
        s0_wstrb  = m_wstrb;
        s0_wlast  = m_wlast;
        s0_wvalid = m_wvalid && !wsel_conf;

        s1_wdata  = m_wdata;
        s1_wstrb  = m_wstrb;
        s1_wlast  = m_wlast;
        s1_wvalid = m_wvalid &&  wsel_conf;
    end
    assign m_wready = wsel_conf ? s1_wready : s0_wready;

    // R routing
    assign m_rid    = rsel_conf ? s1_rid    : s0_rid;
    assign m_rdata  = rsel_conf ? s1_rdata  : s0_rdata;
    assign m_rresp  = rsel_conf ? s1_rresp  : s0_rresp;
    assign m_rlast  = rsel_conf ? s1_rlast  : s0_rlast;
    assign m_rvalid = rsel_conf ? s1_rvalid : s0_rvalid;
    always @(*) begin
        s0_rready = m_rready && !rsel_conf;
        s1_rready = m_rready &&  rsel_conf;
    end

    // B routing
    assign m_bid    = wsel_conf ? s1_bid    : s0_bid;
    assign m_bresp  = wsel_conf ? s1_bresp  : s0_bresp;
    assign m_bvalid = wsel_conf ? s1_bvalid : s0_bvalid;
    always @(*) begin
        s0_bready = m_bready && !wsel_conf;
        s1_bready = m_bready &&  wsel_conf;
    end
endmodule
