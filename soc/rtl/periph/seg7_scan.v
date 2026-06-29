`timescale 1ns/1ps
// 8-digit time-multiplexed seven-segment scanner (board-level display driver).
// Renders a 32-bit value as 8 hexadecimal digits: nibble i drives digit i, where
// digit 0 corresponds to an[0] (typically the rightmost display).
//
// Active levels are parameterized so the same RTL fits common-anode or
// common-cathode panels:
//   SEG_ACTIVE_LOW = 1 : a segment lights when its seg[] bit is 0 (common-anode)
//   AN_ACTIVE_LOW  = 1 : a digit is enabled when its an[] bit is 0
// Segment bit order: seg = {dp, g, f, e, d, c, b, a}  (seg[0]=a, seg[7]=dp).
// dp is always off here.
//
// SCAN_DIV_BITS sets the per-digit dwell time = 2^SCAN_DIV_BITS clk cycles.
// At 50 MHz, 2^16 -> ~1.3 ms/digit -> ~95 Hz full-panel refresh (flicker-free).
module seg7_scan #(
    parameter SCAN_DIV_BITS = 16,
    parameter SEG_ACTIVE_LOW = 1'b1,
    parameter AN_ACTIVE_LOW  = 1'b1
)(
    input             clk,
    input             reset,      // active-high, synchronous
    input      [31:0] value,
    output     [7:0]  seg,
    output     [7:0]  an
);
    // Free-running refresh counter; the top 3 bits select the active digit.
    reg [SCAN_DIV_BITS+2:0] cnt;
    always @(posedge clk) begin
        if (reset) cnt <= {(SCAN_DIV_BITS+3){1'b0}};
        else       cnt <= cnt + 1'b1;
    end
    wire [2:0] sel = cnt[SCAN_DIV_BITS+2:SCAN_DIV_BITS];

    // Pick the nibble for the active digit.
    reg [3:0] nib;
    always @* begin
        case (sel)
            3'd0: nib = value[ 3: 0];
            3'd1: nib = value[ 7: 4];
            3'd2: nib = value[11: 8];
            3'd3: nib = value[15:12];
            3'd4: nib = value[19:16];
            3'd5: nib = value[23:20];
            3'd6: nib = value[27:24];
            3'd7: nib = value[31:28];
        endcase
    end

    // Hex -> active-high segment pattern {g,f,e,d,c,b,a}.
    reg [6:0] segh;
    always @* begin
        case (nib)
            4'h0: segh = 7'b0111111;
            4'h1: segh = 7'b0000110;
            4'h2: segh = 7'b1011011;
            4'h3: segh = 7'b1001111;
            4'h4: segh = 7'b1100110;
            4'h5: segh = 7'b1101101;
            4'h6: segh = 7'b1111101;
            4'h7: segh = 7'b0000111;
            4'h8: segh = 7'b1111111;
            4'h9: segh = 7'b1101111;
            4'ha: segh = 7'b1110111;
            4'hb: segh = 7'b1111100;
            4'hc: segh = 7'b0111001;
            4'hd: segh = 7'b1011110;
            4'he: segh = 7'b1111001;
            4'hf: segh = 7'b1110001;
        endcase
    end

    wire [7:0] anh      = (8'b1 << sel);   // one-hot active-high digit enable
    wire [7:0] seg_high = {1'b0, segh};    // dp off, active-high

    assign seg = SEG_ACTIVE_LOW ? ~seg_high : seg_high;
    assign an  = AN_ACTIVE_LOW  ? ~anh      : anh;
endmodule
