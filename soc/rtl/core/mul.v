`timescale 1ns/1ps

//-----------------------------------------------------------------------------
// mul — 32×32 signed/unsigned multiplier (DSP48E1-inferred)
//
// Replaces the original Booth-encoded Wallace-tree LUT implementation with
// a behavioral multiply that Vivado infers onto DSP48E1 hard macros.
// Latency: 1 cycle (same as original), matching the dep_need_stall=1 contract
// in exe_stage.v.
//
// Architecture: input registers (absorbed as DSP AREG/BREG) →
// combinational DSP multiply (MREG=0) → wire output.
// The input register breaks the long EXE→DSP combinational path; the DSP
// clock-to-output penalty (-0.231 ns post-route @62 MHz) is recovered by
// dropping the PLL to 60 MHz.
//
// XC7A200T has 740 DSP48E1 slices; this uses ~4 of them per 32×32 multiply.
//-----------------------------------------------------------------------------

module mul(
    input              mul_clk,
    input              reset,
    input              mul_signed,
    input      [31:0]  x,
    input      [31:0]  y,
    output     [63:0]  result
);

//-----------------------------------------------------------------
// Stage 0: input registers (absorbed as DSP AREG/BREG)
//-----------------------------------------------------------------
reg [31:0] x_r, y_r;
reg        mul_signed_r;

always @(posedge mul_clk) begin
    if (reset) begin
        x_r          <= 32'h0;
        y_r          <= 32'h0;
        mul_signed_r <= 1'b0;
    end else begin
        x_r          <= x;
        y_r          <= y;
        mul_signed_r <= mul_signed;
    end
end

//-----------------------------------------------------------------
// Stage 1: combinational DSP multiply (MREG=0, cascaded DSP48E1)
//-----------------------------------------------------------------
wire [63:0] x_ext, y_ext;

assign x_ext = mul_signed_r ? {{32{x_r[31]}}, x_r} : {32'b0, x_r};
assign y_ext = mul_signed_r ? {{32{y_r[31]}}, y_r} : {32'b0, y_r};

(* mult_style = "dsp" *) assign result = x_ext * y_ext;

endmodule
