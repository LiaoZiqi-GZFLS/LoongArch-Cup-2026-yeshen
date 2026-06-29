`timescale 1ns/1ps
// AXI3 slave: 32KB word BRAM @0x1c000000 + MMIO (seg7 write @0x1fb00000, counter read @0x1fb00010).
// Supports INCR bursts (len=0 single / len=3 cache-line). Single master (the CPU core),
// so the AXI3 lock/cache/prot sidebands and wid are intentionally not implemented (a single
// master cannot have outstanding writes under different IDs, so wid-vs-awid ordering is moot).
//
// BRAM inference: the 8192x32 array `mem` is accessed ONLY through a synchronous
// read port (mem_q, with read-enable) and a synchronous byte-write port, both in a
// single clocked block — the canonical Xilinx simple-dual-port template — so Vivado
// maps it to Block RAM (forced via ram_style="block"). The cnt_value/DEFAULT_RD
// selection is moved AFTER the BRAM output (a registered select feeding a small mux),
// because mixing those sources into the read register is what forced the array into
// distributed RAM/LUTRAM before.
module axi_mem_soc #(
    parameter INIT_FILE = "",
    parameter RAM_BASE  = 32'h1c00_0000,
    parameter RAM_WORDS = 8192,          // 32KB
    parameter SEG_ADDR  = 32'h1fb0_0000,
    parameter CNT_ADDR  = 32'h1fb0_0010
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
    localparam [31:0] DEFAULT_RD = 32'hDEAD_DEAD;  // returned for unmapped reads

    (* ram_style = "block" *) reg [31:0] mem [0:RAM_WORDS-1];
    integer k;
    initial begin
        for (k=0;k<RAM_WORDS;k=k+1) mem[k]=32'b0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    function in_ram(input [31:0] a);
        in_ram = (a >= RAM_BASE) && (a < RAM_BASE + RAM_WORDS*4);
    endfunction
    function [RAM_IDX_W-1:0] ram_idx(input [31:0] a);   // word index, 13 bits covers 8192
        ram_idx = (a - RAM_BASE) >> 2;
    endfunction

    // ---------------- Read channel: control FSM ----------------
    // The FSM owns only handshake/sequencing state; the read DATA path is the BRAM
    // port below. Keeping data out of the FSM is what lets `mem` infer as Block RAM.
    localparam R_IDLE=1'b0, R_DATA=1'b1;
    reg        rstate;
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
                    rstate<=R_DATA;
                    rvalid<=1'b1; rlast<=(arlen==8'b0);
                end
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

    // ---------------- Read DATA path: BRAM read port + post-mux ----------------
    // rd_byte_addr = the address whose data must be valid NEXT cycle:
    //   * AR accept (R_IDLE)               -> araddr        (beat 0)
    //   * beat consumed, more to go        -> r_addr + 4    (next INCR beat)
    //   * otherwise (idle / master stall)  -> r_addr        (hold current beat)
    // rd_load gates the BRAM output register + the select pipeline so that a stalled
    // R beat (rvalid && !rready) holds rdata stable, as AXI requires — in particular a
    // stalled counter read must not let cnt_value advance under the master.
    wire [31:0] rd_byte_addr =
        (rstate==R_IDLE)             ? araddr         :
        (rvalid && rready && !rlast) ? (r_addr+32'd4) :
                                       r_addr;
    wire rd_load =
        (rstate==R_IDLE && arvalid && arready)        // latch beat 0
     || (rstate==R_DATA && rvalid && rready && !rlast); // latch next beat

    wire rd_is_ram = in_ram(rd_byte_addr);
    wire rd_is_cnt = (rd_byte_addr == CNT_ADDR);

    reg [31:0] mem_q;          // BRAM registered read output
    reg        sel_ram, sel_cnt;
    reg [31:0] cnt_q;

    // BRAM block: one byte-write port + one read port, single clocked process.
    always @(posedge clk) begin
        if (wmem_we) begin
            if (wstrb[0]) mem[ram_idx(w_addr)][ 7: 0] <= wdata[ 7: 0];
            if (wstrb[1]) mem[ram_idx(w_addr)][15: 8] <= wdata[15: 8];
            if (wstrb[2]) mem[ram_idx(w_addr)][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[ram_idx(w_addr)][31:24] <= wdata[31:24];
        end
        if (rd_load) mem_q <= mem[ram_idx(rd_byte_addr)];
    end

    // select pipeline aligned to the 1-cycle BRAM read latency
    always @(posedge clk) begin
        if (reset) begin sel_ram<=1'b0; sel_cnt<=1'b0; cnt_q<=32'b0; end
        else if (rd_load) begin
            sel_ram <= rd_is_ram;
            sel_cnt <= rd_is_cnt;
            cnt_q   <= cnt_value;
        end
    end

    // final read data: BRAM word, or captured counter, or dead-beef for unmapped reads
    always @(*) rdata = sel_ram ? mem_q : (sel_cnt ? cnt_q : DEFAULT_RD);

    // ---------------- Write channel ----------------
    localparam W_IDLE=2'd0, W_DATA=2'd1, W_RESP=2'd2;
    reg [1:0]  wstate;
    reg [31:0] w_addr;
    // BRAM write-enable: a RAM-targeted write beat being accepted in W_DATA.
    wire wmem_we = (wstate==W_DATA) && wvalid && wready && in_ram(w_addr);
    always @(posedge clk) begin
        if (reset) begin
            wstate<=W_IDLE; awready<=1'b1; wready<=1'b0; bvalid<=1'b0; bid<=4'b0;
            seg7_we<=1'b0; seg7_wdata<=32'b0;
            w_addr<=32'b0;
        end else begin
            seg7_we<=1'b0;                         // default: pulse 1 cycle
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
                        // RAM writes land in the BRAM block (wmem_we); here we only
                        // handle the MMIO seg7 register and beat sequencing.
                        if (!in_ram(w_addr) && (w_addr==SEG_ADDR)) begin
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
