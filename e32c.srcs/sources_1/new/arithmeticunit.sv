`timescale 1ns / 1ps

`include "shared.vh"

module arithmeticlogicunit(
	input wire enable,
	output bit [31:0] aluout = 32'd0,
	input wire [2:0] func3,
	input wire [31:0] val1,
	input wire [31:0] val2,
	input wire [3:0] aluop );
	
wire [9:0] aluonehot = {
	aluop == `alu_add ? 1'b1:1'b0,
	aluop == `alu_sub ? 1'b1:1'b0,
	aluop == `alu_sll ? 1'b1:1'b0,
	aluop == `alu_slt ? 1'b1:1'b0,
	aluop == `alu_sltu ? 1'b1:1'b0,
	aluop == `alu_xor ? 1'b1:1'b0,
	aluop == `alu_srl ? 1'b1:1'b0,
	aluop == `alu_sra ? 1'b1:1'b0,
	aluop == `alu_or ? 1'b1:1'b0,
	aluop == `alu_and ? 1'b1:1'b0 };

wire [31:0] vsum = val1 + val2;
wire [31:0] vdiff = val1 + (~val2 + 32'd1); // val1 - val2;
wire [31:0] vshl = val1 << val2[4:0];
wire [31:0] vsless = $signed(val1) < $signed(val2) ? 32'd1 : 32'd0;
wire [31:0] vless = val1 < val2 ? 32'd1 : 32'd0;
wire [31:0] vxor = val1 ^ val2;
wire [31:0] vshr = val1 >> val2[4:0];
wire [31:0] vsra = $signed(val1) >>> val2[4:0];
wire [31:0] vor = val1 | val2;
wire [31:0] vand = val1 & val2;

// integer alu
// aluout will generate a latch
always_comb begin
	if (enable) begin
		case (1'b1)
			// integer ops
			default/*aluonehot[9]*/: aluout = vsum;
			aluonehot[8]: aluout = vdiff;
			aluonehot[7]: aluout = vshl;
			aluonehot[6]: aluout = vsless;
			aluonehot[5]: aluout = vless;
			aluonehot[4]: aluout = vxor;
			aluonehot[3]: aluout = vshr;
			aluonehot[2]: aluout = vsra;
			aluonehot[1]: aluout = vor;
			aluonehot[0]: aluout = vand;
		endcase
	end else begin
		// result is latched
	end
end

endmodule
