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

// integer alu
// aluout will generate a latch
always_comb begin
	if (enable) begin
		case (1'b1)
			// integer ops
			default/*aluonehot[9]*/: aluout = val1 + val2;
			aluonehot[8]: aluout = val1 + (~val2 + 32'd1); // val1 - val2;
			aluonehot[7]: aluout = val1 << val2[4:0];
			aluonehot[6]: aluout = $signed(val1) < $signed(val2) ? 32'd1 : 32'd0;
			aluonehot[5]: aluout = val1 < val2 ? 32'd1 : 32'd0;
			aluonehot[4]: aluout = val1 ^ val2;
			aluonehot[3]: aluout = val1 >> val2[4:0];
			aluonehot[2]: aluout = $signed(val1) >>> val2[4:0];
			aluonehot[1]: aluout = val1 | val2;
			aluonehot[0]: aluout = val1 & val2;
		endcase
	end else begin
		// result is latched
	end
end

endmodule
