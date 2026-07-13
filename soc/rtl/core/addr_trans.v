`timescale 1ns/1ps
`include "csr.h"

// Direct-Address (DA) mode address translation stub.
//
// The contest target is a bare-metal LA32R system with NO TLB/MMU virtual
// memory support (see Description.md: "禁止实现 ... TLB/MMU虚拟内存相关特权指令").
// openLA500 originally implements a 32-entry TLB, but the SoC runs with
// CRMD.DA=1 / CRMD.PG=0 from reset, so translation is already effectively
// a pass-through. This module keeps the original interface to avoid rewiring
// mycpu_top and the pipeline stages, but replaces the internal behaviour with
// pure DA-mode passthrough and constant "TLB hit" sideband outputs.
//
// The underlying tlb_entry instance is intentionally retained with dangling
// outputs; Vivado removes it as dead logic during synthesis.
module addr_trans
#(
    parameter TLBNUM = 32
)
(
    input                  clk                  ,
    input  [ 9:0]          asid                 ,
    //trans mode
    input                  inst_addr_trans_en   ,
    input                  data_addr_trans_en   ,
    //inst addr trans
    input                  inst_fetch           ,
    input  [31:0]          inst_vaddr           ,
    input                  inst_dmw0_en         ,
    input                  inst_dmw1_en         ,
    output [ 7:0]          inst_index           ,
    output [19:0]          inst_tag             ,
    output [ 3:0]          inst_offset          ,
    output                 inst_tlb_found       ,
    output                 inst_tlb_v           ,
    output                 inst_tlb_d           ,
    output [ 1:0]          inst_tlb_mat         ,
    output [ 1:0]          inst_tlb_plv         ,
    //data addr trans
    input                  data_fetch           ,
    input  [31:0]          data_vaddr           ,
    input                  data_dmw0_en         ,
    input                  data_dmw1_en         ,
    input                  cacop_op_mode_di     ,
    output [ 7:0]          data_index           ,
    output [19:0]          data_tag             ,
    output [ 3:0]          data_offset          ,
    output                 data_tlb_found       ,
    output [ 4:0]          data_tlb_index       ,
    output                 data_tlb_v           ,
    output                 data_tlb_d           ,
    output [ 1:0]          data_tlb_mat         ,
    output [ 1:0]          data_tlb_plv         ,
    //tlbwi tlbwr tlb write
    input                  tlbfill_en           ,
    input                  tlbwr_en             ,
    input  [ 4:0]          rand_index           ,
    input  [31:0]          tlbehi_in            ,
    input  [31:0]          tlbelo0_in           ,
    input  [31:0]          tlbelo1_in           ,
    input  [31:0]          tlbidx_in            ,
    input  [ 5:0]          ecode_in             ,
    //tlbr tlb read
    output [31:0]          tlbehi_out           ,
    output [31:0]          tlbelo0_out          ,
    output [31:0]          tlbelo1_out          ,
    output [31:0]          tlbidx_out           ,
    output [ 9:0]          asid_out             ,
    //invtlb
    input                  invtlb_en            ,
    input  [ 9:0]          invtlb_asid          ,
    input  [18:0]          invtlb_vpn           ,
    input  [ 4:0]          invtlb_op            ,
    //from csr
    input  [31:0]          csr_dmw0             ,
    input  [31:0]          csr_dmw1             ,
    input                  csr_da               ,
    input                  csr_pg
);

    // Address buffers, identical to the original behaviour.
    reg [31:0] inst_vaddr_buffer;
    reg [31:0] data_vaddr_buffer;

    always @(posedge clk) begin
        if (inst_fetch) inst_vaddr_buffer <= inst_vaddr;
        if (data_fetch) data_vaddr_buffer <= data_vaddr;
    end

    // In DA mode virtual address == physical address.
    wire [31:0] inst_paddr = inst_vaddr_buffer;
    wire [31:0] data_paddr = data_vaddr_buffer;

    // Cache uses index/tag/offset directly from the physical address.
    assign inst_offset = inst_vaddr[3:0];
    assign inst_index  = inst_vaddr[11:4];
    assign inst_tag    = inst_paddr[31:12];

    assign data_offset = data_vaddr[3:0];
    assign data_index  = data_vaddr[11:4];
    assign data_tag    = data_paddr[31:12];

    // Constant TLB sideband outputs: "found, valid, dirty, strongly-ordered
    // uncacheable (MAT=0), privileged level 0". These signals are only
    // examined when inst_addr_trans_en / data_addr_trans_en is high, which
    // only happens in pg_mode (never, because this system is always DA).
    assign inst_tlb_found = 1'b1;
    assign inst_tlb_v     = 1'b1;
    assign inst_tlb_d     = 1'b1;
    assign inst_tlb_mat   = 2'b00;
    assign inst_tlb_plv   = 2'b00;

    assign data_tlb_found = 1'b1;
    assign data_tlb_index = 5'b0;
    assign data_tlb_v     = 1'b1;
    assign data_tlb_d     = 1'b1;
    assign data_tlb_mat   = 2'b00;
    assign data_tlb_plv   = 2'b00;

    // TLB read ports are unused in DA mode; return zero.
    assign tlbehi_out  = 32'b0;
    assign tlbelo0_out = 32'b0;
    assign tlbelo1_out = 32'b0;
    assign tlbidx_out  = 32'b0;
    assign asid_out    = 10'b0;

    // TLB/MMU is NOT implemented for the LoongArch Cup (DA mode only).
    // The 32-entry CAM tlb_entry instance is removed entirely to reduce
    // routing congestion.  All TLB sideband outputs are already hardwired
    // to DA-safe constants above.
endmodule
