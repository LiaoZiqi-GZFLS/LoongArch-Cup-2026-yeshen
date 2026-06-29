`timescale 1ns/1ps
// Self-checking tb for seg7_scan: verifies hex decode, one-hot digit scan, and
// that the active-level parameters invert seg/an as specified.
module tb_seg7_scan;
  reg clk = 0, reset = 1;
  reg  [31:0] value;
  wire [7:0]  seg, an;       // common-anode default (active-low)
  wire [7:0]  seg_h, an_h;   // active-high variant, lockstep cross-check
  integer i, k, active, errors;
  reg [6:0] segh;
  reg [3:0] nib;

  // SCAN_DIV_BITS=0 -> one cycle per digit, full scan every 8 cycles.
  seg7_scan #(.SCAN_DIV_BITS(0))
    dut(.clk(clk), .reset(reset), .value(value), .seg(seg), .an(an));
  seg7_scan #(.SCAN_DIV_BITS(0), .SEG_ACTIVE_LOW(0), .AN_ACTIVE_LOW(0))
    dut_h(.clk(clk), .reset(reset), .value(value), .seg(seg_h), .an(an_h));

  always #5 clk = ~clk;

  function [6:0] hex2seg;     // active-high {g,f,e,d,c,b,a}
    input [3:0] h;
    case (h)
      4'h0: hex2seg = 7'b0111111; 4'h1: hex2seg = 7'b0000110;
      4'h2: hex2seg = 7'b1011011; 4'h3: hex2seg = 7'b1001111;
      4'h4: hex2seg = 7'b1100110; 4'h5: hex2seg = 7'b1101101;
      4'h6: hex2seg = 7'b1111101; 4'h7: hex2seg = 7'b0000111;
      4'h8: hex2seg = 7'b1111111; 4'h9: hex2seg = 7'b1101111;
      4'ha: hex2seg = 7'b1110111; 4'hb: hex2seg = 7'b1111100;
      4'hc: hex2seg = 7'b0111001; 4'hd: hex2seg = 7'b1011110;
      4'he: hex2seg = 7'b1111001; 4'hf: hex2seg = 7'b1110001;
    endcase
  endfunction

  initial begin
    errors = 0;
    value  = 32'h76543210;     // digit i shows nibble i
    @(negedge clk); reset = 0;

    for (k = 0; k < 16; k = k + 1) begin     // two full scans
      @(negedge clk);
      // exactly one digit enabled (active-low: a single 0 bit)
      active = -1;
      for (i = 0; i < 8; i = i + 1)
        if (an[i] === 1'b0) begin
          if (active != -1) begin
            $display("FAIL multiple digits active an=%b", an); errors = errors + 1;
          end
          active = i;
        end
      if (active == -1) begin
        $display("FAIL no digit active an=%b", an); errors = errors + 1;
      end else begin
        nib  = value[active*4 +: 4];
        segh = hex2seg(nib);
        if (seg !== ~{1'b0, segh}) begin
          $display("FAIL digit %0d nib %h seg=%b exp=%b", active, nib, seg, ~{1'b0, segh});
          errors = errors + 1;
        end
      end
      // polarity parameterization: active-high instance is the bitwise inverse
      if (seg_h !== ~seg) begin $display("FAIL seg polarity seg_h=%b seg=%b", seg_h, seg); errors = errors + 1; end
      if (an_h  !== ~an ) begin $display("FAIL an polarity an_h=%b an=%b",  an_h,  an ); errors = errors + 1; end
    end

    if (errors == 0) $display("PASS tb_seg7_scan");
    else             $display("FAIL tb_seg7_scan (%0d errors)", errors);
    $finish;
  end
endmodule
