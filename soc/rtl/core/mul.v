`timescale 1ns/1ps

//-----------------------------------------------------------------------------
// mul — 32×32 signed/unsigned multiplier (DSP48E1-inferred)
//
// Replaces the original Booth-encoded Wallace-tree LUT implementation with
// a behavioral multiply that Vivado infers onto DSP48E1 hard macros.
// Latency: 1 cycle (same as original), matching the dep_need_stall=1 contract
// in exe_stage.v.
//
// Architecture: combinational DSP multiply → output register (PREG).
// This breaks the DSP CLK→fabric→destination critical path by using the
// DSP48E1's internal output register (PREG), whose Tcko is ~0.3 ns vs.
// 2-3 ns for the combinational multiply→fabric route.
//
// XC7A200T has 740 DSP48E1 slices; this uses ~4 of them per 32×32 multiply.
//-----------------------------------------------------------------------------

module mul(
    input              mul_clk,
    input              reset,
    input              mul_signed,
    input      [31:0]  x,
    input      [31:0]  y,
    output reg [63:0]  result
);

//-----------------------------------------------------------------
// Stage 0: combinational DSP multiply (infers DSP48E1 cascade)
//
// In Verilog-2001, a × b yields max(width(a),width(b)) bits.
// To capture the full 64-bit product of two 32-bit numbers we must
// extend one operand to 64 bits. The lower 64 bits of the extended
// product equal the true mathematical product.
//
// Signed:   {{32{x[31]}}, x}  ×  {{32{y[31]}}, y}
// Unsigned: {32'b0, x}         ×  {32'b0, y}
//-----------------------------------------------------------------
wire [63:0] x_ext, y_ext;
wire [63:0] product_comb;

assign x_ext = mul_signed ? {{32{x[31]}}, x} : {32'b0, x};
assign y_ext = mul_signed ? {{32{y[31]}}, y} : {32'b0, y};

(* mult_style = "dsp" *) assign product_comb = x_ext * y_ext;

//-----------------------------------------------------------------
// Stage 1: output register (matches original 1-cycle latency)
//
// The original mul registers Booth partial products, then runs
// Wallace tree + final adder combinationally to the output.
// We register the final product instead — same 1-cycle latency,
// but the DSP48E1's PREG Tcko is far smaller than the fabric
// clock-to-output + Wallace + adder path.
//-----------------------------------------------------------------
always @(posedge mul_clk) begin
    if (reset)
        result <= 64'h0;
    else
        result <= product_comb;
end

endmodule
