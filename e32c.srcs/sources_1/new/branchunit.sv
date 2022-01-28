`timescale 1ns / 1ps

`include "shared.vh"

module branchlogicunit(
	input wire enable,
	output bit branchout = 1'b0,
	input wire [31:0] val1,
	input wire [31:0] val2,
	input wire [2:0] bluop);

wire [5:0] aluonehot = {
	bluop == `blu_eq ? 1'b1 : 1'b0,
	bluop == `blu_ne ? 1'b1 : 1'b0,
	bluop == `blu_l ? 1'b1 : 1'b0,
	bluop == `blu_ge ? 1'b1 : 1'b0,
	bluop == `blu_lu ? 1'b1 : 1'b0,
	bluop == `blu_geu ? 1'b1 : 1'b0 };

wire eq = val1 == val2 ? 1'b1:1'b0;
wire sless = $signed(val1) < $signed(val2) ? 1'b1:1'b0;
wire less = val1 < val2 ? 1'b1:1'b0;

// branch alu
always_comb begin
	if (enable) begin
		case (1'b1)
			// branch alu
			aluonehot[5]:	branchout = eq;
			aluonehot[4]:	branchout = ~eq;
			aluonehot[3]:	branchout = sless;
			aluonehot[2]:	branchout = ~sless;
			aluonehot[1]:	branchout = less;
			/*aluonehot[0]*/
			default:		branchout = ~less;
		endcase
	end else begin
		//
	end
end

endmodule
