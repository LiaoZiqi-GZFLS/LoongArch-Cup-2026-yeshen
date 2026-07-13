`timescale 1ns/1ps

//-----------------------------------------------------------------------------
// mul — 32×32 signed/unsigned multiplier (DSP48E1-inferred)
//
// Replaces the original Booth-encoded Wallace-tree LUT implementation with
// a behavioral multiply that Vivado infers onto DSP48E1 hard macros.
// Latency: 1 cycle (same as original), matching the dep_need_stall=1 contract
// in exe_stage.v.
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
// Stage 0: input registers (matches original Booth-register position)
//
// The original mul registers Booth-encoded partial products, then
// runs Wallace tree + final adder combinationally to the output.
// We register the raw operands instead, then let DSP48E1 hard macros
// produce the result combinationally – same 1-cycle latency, but the
// slow LUT Wallace tree becomes a fast DSP48E1 cascade.
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
// Stage 1: combinational DSP multiply (infers DSP48E1 cascade)
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

assign x_ext = mul_signed_r ? {{32{x_r[31]}}, x_r} : {32'b0, x_r};
assign y_ext = mul_signed_r ? {{32{y_r[31]}}, y_r} : {32'b0, y_r};

(* mult_style = "dsp" *) assign result = x_ext * y_ext;

endmodule
