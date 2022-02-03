`timescale 1ns / 1ps

`include "shared.vh"

module multiplier(
    input wire clk,					// clock input
    input wire resetn,				// reset line
    input wire start,				// kick multiply operation (hold for one clock)
    output logic busy = 1'b0,		// multiplier busy
    input wire [2:0] func3,			// to determine which mul op this is
    input wire [31:0] multiplicand,	// input a
    input wire [31:0] multiplier,	// input b
    output logic [31:0] product );	// result

logic [32:0] a = 33'd0;
logic [32:0] b = 33'd0;
logic [3:0] n = 4'd0;
wire [65:0] dspproduct;

multDSP mulsignedsigned(
	.CLK(clk),
	.A(a),
	.B(b),
	.P(dspproduct),
	.CE(~reset & (start | busy)) );

always_ff @(posedge clk) begin
	if (~resetn) begin
		//busy <= 1'b0;
	end else begin
		if (start) begin

			unique case (func3)
				`f3_mul, `f3_mulh: begin
					a <= {multiplicand[31], multiplicand};
					b <= {multiplier[31], multiplier};
				end
				`f3_mulhsu: begin
					a <= {multiplicand[31], multiplicand};
					b <= {1'b0, multiplier};
				end
				`f3_mulhu: begin
					a <= {1'b0, multiplicand};
					b <= {1'b0, multiplier};
				end
			endcase
			// can use 1 clock latency for
			// multipliers on artyz7-20, 7 is ok on artya7-100t for area
			n <= 7;
			busy <= 1'b1;
		end else begin
			if (busy) begin
				if (n == 0) begin
					unique case (func3)
						`f3_mul: begin
							product <= dspproduct[31:0];
						end
						default : begin // `f3_mulh, `f3_mulhsu, `f3_mulhu
							product <= dspproduct[63:32]; // or is this 64:33 ?
						end
					endcase
					busy <= 1'b0;
				end else begin
					n <= n - 4'd1;
				end 
			end else begin
				product <= 32'd0;
			end
		end
	end
end

endmodule
