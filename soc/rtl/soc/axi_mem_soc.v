`timescale 1ns/1ps
// AXI3 slave: word BRAM @0x1c000000 + data RAM @0x000d0000 + eximm scratch @0x001d0000
// + demo MMIO (seg7 write @0x1fb00000, counter read @0x1fb00010).
// Default RAM_WORDS = 262144 (1 MB) so the 2026 ChipLab functional / performance test
// binaries fit.  The two extra small BRAMs cover the ChipLab functional test's absolute
// data addresses (0xd0000 region) and exception scratch (DATABASE = 0x1d0000).
// Supports INCR bursts (len=0 single / len=3 cache-line). Single master (the CPU core),
// so the AXI3 lock/cache/prot sidebands and wid are intentionally not implemented (a single
// master cannot have outstanding writes under different IDs, so wid-vs-awid ordering is moot).
//
// BRAM inference: each memory array is accessed ONLY through a synchronous read port
// (registered output) and a synchronous byte-write port, both in a single clocked block
// -- the canonical Xilinx simple-dual-port template -- so Vivado maps them to Block RAM.
module axi_mem_soc #(
    parameter INIT_FILE = "",
    parameter RAM_BASE   = 32'h1c00_0000,
    parameter RAM_WORDS  = 262144,        // 1 MB (ChipLab func/perf code + perf data)
    parameter DATA_BASE  = 32'h000c_f000,
    parameter DATA_WORDS = 18'd18432,       // 72 KB: covers func-test data region ~0xcf000..0xe0fff
    parameter EXIMM_BASE  = 32'h001d_0000,
    parameter EXIMM_WORDS = 1024,         // 4 KB (ChipLab exception scratch)
    parameter SCRATCH_BASE  = 32'hbfe0_0000,
    parameter SCRATCH_WORDS = 16384,      // 64 KB (ChipLab perf control/status scratch)
    parameter SEG_ADDR   = 32'h1fb0_0000,
    parameter CNT_ADDR   = 32'h1fb0_0010,
    parameter UART_BASE  = 32'hbfe0_01e0,
    parameter UART_SIZE  = 8              // 16550 UART register window
)(
    input             clk,
    input             reset,
    // AR / R
    input      [ 3:0] arid,   input [31:0] araddr, input [7:0] arlen,
    input      [ 2:0] arsize, input [ 1:0] arburst, input arvalid, output reg arready,
    output reg [ 3:0] rid,    output reg [31:0] rdata, output [1:0] rresp,
    output reg        rlast,  output reg rvalid, input rready,
    // AW / W / B
    input      [ 3:0] awid,   input [31:0] awaddr, input [7:0] awlen,
    input      [ 2:0] awsize, input [ 1:0] awburst, input awvalid, output reg awready,
    input      [31:0] wdata,  input [3:0] wstrb, input wlast, input wvalid, output reg wready,
    output reg [ 3:0] bid,    output [1:0] bresp, output reg bvalid, input bready,
    // peripheral hooks
    output reg        seg7_we,
    output reg [31:0] seg7_wdata,
    input      [31:0] cnt_value
);
    assign rresp = 2'b00;
    assign bresp = 2'b00;

    localparam RAM_IDX_W      = $clog2(RAM_WORDS);
    localparam DATA_IDX_W     = $clog2(DATA_WORDS);
    localparam EXIMM_IDX_W    = $clog2(EXIMM_WORDS);
    localparam SCRATCH_IDX_W  = $clog2(SCRATCH_WORDS);
    localparam [31:0] DEFAULT_RD = 32'hDEAD_DEAD;  // returned for unmapped reads

    (* ram_style = "block" *) reg [31:0] mem     [0:RAM_WORDS-1];
    (* ram_style = "block" *) reg [31:0] dmem    [0:DATA_WORDS-1];
    (* ram_style = "block" *) reg [31:0] emem    [0:EXIMM_WORDS-1];
    (* ram_style = "block" *) reg [31:0] scratch [0:SCRATCH_WORDS-1];
    integer k;
    initial begin
        for (k=0;k<RAM_WORDS;k=k+1)      mem[k]     = 32'b0;
        for (k=0;k<DATA_WORDS;k=k+1)    dmem[k]    = 32'b0;
        for (k=0;k<EXIMM_WORDS;k=k+1)   emem[k]    = 32'b0;
        for (k=0;k<SCRATCH_WORDS;k=k+1) scratch[k] = 32'b0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    function in_ram(input [31:0] a);
        in_ram = (a >= RAM_BASE) && (a < RAM_BASE + RAM_WORDS*4);
    endfunction
    function [RAM_IDX_W-1:0] ram_idx(input [31:0] a);
        ram_idx = (a - RAM_BASE) >> 2;
    endfunction

    function in_data(input [31:0] a);
        in_data = (a >= DATA_BASE) && (a < DATA_BASE + DATA_WORDS*4);
    endfunction
    function [DATA_IDX_W-1:0] data_idx(input [31:0] a);
        data_idx = (a - DATA_BASE) >> 2;
    endfunction

    function in_eximm(input [31:0] a);
        in_eximm = (a >= EXIMM_BASE) && (a < EXIMM_BASE + EXIMM_WORDS*4);
    endfunction
    function [EXIMM_IDX_W-1:0] eximm_idx(input [31:0] a);
        eximm_idx = (a - EXIMM_BASE) >> 2;
    endfunction

    function in_scratch(input [31:0] a);
        in_scratch = (a >= SCRATCH_BASE) && (a < SCRATCH_BASE + SCRATCH_WORDS*4);
    endfunction
    function [SCRATCH_IDX_W-1:0] scratch_idx(input [31:0] a);
        scratch_idx = (a - SCRATCH_BASE) >> 2;
    endfunction

    function in_uart(input [31:0] a);
        in_uart = (a >= UART_BASE) && (a < UART_BASE + UART_SIZE);
    endfunction
    function [2:0] uart_idx(input [31:0] a);
        uart_idx = a[2:0];
    endfunction

    // ---------------- Write channel declarations (placed before read data path
    // because Vivado/xvlog requires a wire to be declared before use) --------
    localparam W_IDLE=2'd0, W_DATA=2'd1, W_RESP=2'd2;
    reg [1:0]  wstate;
    reg [31:0] w_addr;
    wire wmem_we     = (wstate==W_DATA) && wvalid && wready && in_ram(w_addr);
    wire wdmem_we    = (wstate==W_DATA) && wvalid && wready && in_data(w_addr);
    wire wemem_we    = (wstate==W_DATA) && wvalid && wready && in_eximm(w_addr);
    wire wscratch_we = (wstate==W_DATA) && wvalid && wready && in_scratch(w_addr);

    // ---------------- Read channel: control FSM ----------------
    // One-cycle read latency: address is accepted in R_IDLE, the BRAM read is
    // started in R_WAIT, and data is returned in R_DATA.  rvalid is never
    // asserted until the first beat's data is actually available.
    localparam R_IDLE=2'd0, R_WAIT=2'd1, R_DATA=2'd2;
    reg [1:0]  rstate;
    reg [31:0] r_addr;
    reg [ 7:0] r_cnt;       // remaining beats
    always @(posedge clk) begin
        if (reset) begin
            rstate<=R_IDLE; arready<=1'b1; rvalid<=1'b0; rlast<=1'b0; rid<=4'b0;
            r_addr<=32'b0; r_cnt<=8'b0;
        end else case (rstate)
            R_IDLE: begin
                rvalid<=1'b0; rlast<=1'b0; arready<=1'b1;
                if (arvalid && arready) begin
                    arready<=1'b0; rid<=arid; r_addr<=araddr; r_cnt<=arlen;
                    rstate<=R_WAIT;
                end
            end
            R_WAIT: begin
                rstate<=R_DATA;
                rvalid<=1'b1;
                rlast<=(r_cnt==8'b0);
            end
            R_DATA: begin
                if (rvalid && rready) begin
                    if (rlast) begin
                        rvalid<=1'b0; rlast<=1'b0; arready<=1'b1; rstate<=R_IDLE;
                    end else begin
                        r_addr <= r_addr + 32'd4;        // INCR, word beats
                        r_cnt  <= r_cnt - 8'd1;
                        rlast  <= (r_cnt == 8'd1);
                    end
                end
            end
        endcase
    end

    // ---------------- Read DATA path: BRAM read ports + post-mux ----------------
    wire [31:0] rd_byte_addr =
        (rstate==R_WAIT)             ? r_addr         :
        (rvalid && rready && !rlast) ? (r_addr+32'd4) :
                                       r_addr;
    wire rd_load =
        (rstate==R_WAIT)                              // latch beat 0
     || (rstate==R_DATA && rvalid && rready && !rlast); // latch next beat

    wire rd_is_ram     = in_ram(rd_byte_addr);
    wire rd_is_data    = in_data(rd_byte_addr);
    wire rd_is_eximm   = in_eximm(rd_byte_addr);
    wire rd_is_scratch = in_scratch(rd_byte_addr);
    wire rd_is_uart    = in_uart(rd_byte_addr);
    wire rd_is_cnt     = (rd_byte_addr == CNT_ADDR);

    reg [31:0] mem_q, dmem_q, emem_q, scratch_q, uart_q;
    reg        sel_ram, sel_data, sel_eximm, sel_scratch, sel_uart, sel_cnt;
    reg [31:0] cnt_q;

    always @(posedge clk) begin
        if (wmem_we) begin
            if (wstrb[0]) mem[ram_idx(w_addr)][ 7: 0] <= wdata[ 7: 0];
            if (wstrb[1]) mem[ram_idx(w_addr)][15: 8] <= wdata[15: 8];
            if (wstrb[2]) mem[ram_idx(w_addr)][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[ram_idx(w_addr)][31:24] <= wdata[31:24];
        end
        if (wdmem_we) begin
            if (wstrb[0]) dmem[data_idx(w_addr)][ 7: 0] <= wdata[ 7: 0];
            if (wstrb[1]) dmem[data_idx(w_addr)][15: 8] <= wdata[15: 8];
            if (wstrb[2]) dmem[data_idx(w_addr)][23:16] <= wdata[23:16];
            if (wstrb[3]) dmem[data_idx(w_addr)][31:24] <= wdata[31:24];
        end
        if (wemem_we) begin
            if (wstrb[0]) emem[eximm_idx(w_addr)][ 7: 0] <= wdata[ 7: 0];
            if (wstrb[1]) emem[eximm_idx(w_addr)][15: 8] <= wdata[15: 8];
            if (wstrb[2]) emem[eximm_idx(w_addr)][23:16] <= wdata[23:16];
            if (wstrb[3]) emem[eximm_idx(w_addr)][31:24] <= wdata[31:24];
        end
        if (wscratch_we) begin
            if (wstrb[0]) scratch[scratch_idx(w_addr)][ 7: 0] <= wdata[ 7: 0];
            if (wstrb[1]) scratch[scratch_idx(w_addr)][15: 8] <= wdata[15: 8];
            if (wstrb[2]) scratch[scratch_idx(w_addr)][23:16] <= wdata[23:16];
            if (wstrb[3]) scratch[scratch_idx(w_addr)][31:24] <= wdata[31:24];
        end
        if (rd_load) begin
            mem_q      <= rd_is_ram     ? mem[ram_idx(rd_byte_addr)]         : 32'b0;
            dmem_q     <= rd_is_data    ? dmem[data_idx(rd_byte_addr)]       : 32'b0;
            emem_q     <= rd_is_eximm   ? emem[eximm_idx(rd_byte_addr)]      : 32'b0;
            scratch_q  <= rd_is_scratch ? scratch[scratch_idx(rd_byte_addr)] : 32'b0;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            sel_ram<=1'b0; sel_data<=1'b0; sel_eximm<=1'b0; sel_scratch<=1'b0; sel_uart<=1'b0; sel_cnt<=1'b0; cnt_q<=32'b0;
        end else if (rd_load) begin
            sel_ram     <= rd_is_ram;
            sel_data    <= rd_is_data;
            sel_eximm   <= rd_is_eximm;
            sel_scratch <= rd_is_scratch && !rd_is_uart;
            sel_uart    <= rd_is_uart;
            sel_cnt     <= rd_is_cnt;
            cnt_q       <= cnt_value;
            uart_q      <= rd_is_uart ? ((uart_idx(rd_byte_addr) == 3'd5) ? 32'h6060_6060 : 32'b0) : 32'b0;
        end
    end

    always @(*) rdata = sel_ram     ? mem_q      :
                        sel_data    ? dmem_q     :
                        sel_eximm   ? emem_q     :
                        sel_uart    ? uart_q     :
                        sel_scratch ? scratch_q  :
                        sel_cnt     ? cnt_q      : DEFAULT_RD;

    // ---------------- Write channel ----------------
    always @(posedge clk) begin
        if (reset) begin
            wstate<=W_IDLE; awready<=1'b1; wready<=1'b0; bvalid<=1'b0; bid<=4'b0;
            seg7_we<=1'b0; seg7_wdata<=32'b0;
            w_addr<=32'b0;
        end else begin
            seg7_we<=1'b0;
            case (wstate)
                W_IDLE: begin
                    bvalid<=1'b0; awready<=1'b1;
                    if (awvalid && awready) begin
                        awready<=1'b0; bid<=awid; w_addr<=awaddr;
                        wready<=1'b1; wstate<=W_DATA;
                    end
                end
                W_DATA: begin
                    if (wvalid && wready) begin
                        if (!in_ram(w_addr) && !in_data(w_addr) && !in_eximm(w_addr) && !in_scratch(w_addr) && (w_addr==SEG_ADDR)) begin
                            seg7_we<=1'b1; seg7_wdata<=wdata;
                        end
                        w_addr <= w_addr + 32'd4;
                        if (wlast) begin
                            wready<=1'b0; bvalid<=1'b1; wstate<=W_RESP;
                        end
                    end
                end
                W_RESP: begin
                    if (bvalid && bready) begin
                        bvalid<=1'b0; awready<=1'b1; wstate<=W_IDLE;
                    end
                end
            endcase
        end
    end
endmodule
