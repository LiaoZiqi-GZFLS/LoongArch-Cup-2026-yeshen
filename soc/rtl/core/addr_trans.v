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

    // Preserve the tlb_entry instantiation with dangling outputs so we do not
    // have to delete the source file or alter mycpu_top wiring. Vivado removes
    // the resulting dead logic during synthesis.
    wire        s0_found_unused;
    wire [ 4:0] s0_index_unused;
    wire [ 5:0] s0_ps_unused;
    wire [19:0] s0_ppn_unused;
    wire        s0_v_unused;
    wire        s0_d_unused;
    wire [ 1:0] s0_mat_unused;
    wire [ 1:0] s0_plv_unused;

    wire        s1_found_unused;
    wire [ 4:0] s1_index_unused;
    wire [ 5:0] s1_ps_unused;
    wire [19:0] s1_ppn_unused;
    wire        s1_v_unused;
    wire        s1_d_unused;
    wire [ 1:0] s1_mat_unused;
    wire [ 1:0] s1_plv_unused;

    wire [18:0] r_vppn_unused;
    wire [ 9:0] r_asid_unused;
    wire        r_g_unused;
    wire [ 5:0] r_ps_unused;
    wire        r_e_unused;
    wire        r_v0_unused;
    wire        r_d0_unused;
    wire [ 1:0] r_mat0_unused;
    wire [ 1:0] r_plv0_unused;
    wire [19:0] r_ppn0_unused;
    wire        r_v1_unused;
    wire        r_d1_unused;
    wire [ 1:0] r_mat1_unused;
    wire [ 1:0] r_plv1_unused;
    wire [19:0] r_ppn1_unused;

    tlb_entry tlb_entry(
        .clk            (clk                ),
        .s0_fetch       (inst_fetch         ),
        .s0_vppn        (inst_vaddr[31:13]  ),
        .s0_odd_page    (inst_vaddr[12]     ),
        .s0_asid        (asid               ),
        .s0_found       (s0_found_unused    ),
        .s0_index       (s0_index_unused    ),
        .s0_ps          (s0_ps_unused       ),
        .s0_ppn         (s0_ppn_unused      ),
        .s0_v           (s0_v_unused        ),
        .s0_d           (s0_d_unused        ),
        .s0_mat         (s0_mat_unused      ),
        .s0_plv         (s0_plv_unused      ),
        .s1_fetch       (data_fetch         ),
        .s1_vppn        (data_vaddr[31:13]  ),
        .s1_odd_page    (data_vaddr[12]     ),
        .s1_asid        (asid               ),
        .s1_found       (s1_found_unused    ),
        .s1_index       (s1_index_unused    ),
        .s1_ps          (s1_ps_unused       ),
        .s1_ppn         (s1_ppn_unused      ),
        .s1_v           (s1_v_unused        ),
        .s1_d           (s1_d_unused        ),
        .s1_mat         (s1_mat_unused      ),
        .s1_plv         (s1_plv_unused      ),
        .we             (tlbfill_en || tlbwr_en),
        .w_index        (rand_index         ),
        .w_vppn         (tlbehi_in[`VPPN]   ),
        .w_asid         (asid               ),
        .w_g            (1'b0               ),
        .w_ps           (6'd12              ),
        .w_e            (1'b1               ),
        .w_v0           (1'b0               ),
        .w_d0           (1'b0               ),
        .w_plv0         (2'b0               ),
        .w_mat0         (2'b0               ),
        .w_ppn0         (20'b0              ),
        .w_v1           (1'b0               ),
        .w_d1           (1'b0               ),
        .w_plv1         (2'b0               ),
        .w_mat1         (2'b0               ),
        .w_ppn1         (20'b0              ),
        .r_index        (tlbidx_in[`INDEX]  ),
        .r_vppn         (r_vppn_unused      ),
        .r_asid         (r_asid_unused      ),
        .r_g            (r_g_unused         ),
        .r_ps           (r_ps_unused        ),
        .r_e            (r_e_unused         ),
        .r_v0           (r_v0_unused        ),
        .r_d0           (r_d0_unused        ),
        .r_mat0         (r_mat0_unused      ),
        .r_plv0         (r_plv0_unused      ),
        .r_ppn0         (r_ppn0_unused      ),
        .r_v1           (r_v1_unused        ),
        .r_d1           (r_d1_unused        ),
        .r_mat1         (r_mat1_unused      ),
        .r_plv1         (r_plv1_unused      ),
        .r_ppn1         (r_ppn1_unused      ),
        .inv_en         (invtlb_en          ),
        .inv_op         (invtlb_op          ),
        .inv_asid       (invtlb_asid        ),
        .inv_vpn        (invtlb_vpn         )
    );
endmodule
