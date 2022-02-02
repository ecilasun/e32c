`timescale 1ns / 1ps

module unsignedintegerdivider(
    input wire clk,
    input wire resetn,
    input wire start,
    input wire [31:0] dividend,
    input wire [31:0] divisor,
    output wire [31:0] quotient,
    output wire [31:0] remainder,
    output logic busy = 1'b0);

logic [5:0] count;
logic [31:00] reg_q;
logic [31:00] reg_r;
logic [31:00] reg_b;
logic r_sign;
wire [32:0] sub_add = r_sign ? ({reg_r, quotient[31]} + {1'b0, reg_b}) : ({reg_r, quotient[31]} - {1'b0, reg_b});
assign remainder = r_sign ? reg_r + reg_b : reg_r;
assign quotient = reg_q;

always @(posedge clk) begin
    if (~resetn) begin
    	//
    end else begin
        if(start)begin
            reg_r <= 32'b0;
            r_sign <= 0;
            reg_q <= dividend;
            reg_b <= divisor;
            count <= 0;
            busy <= 1;
        end else if(busy) begin
            reg_r <= sub_add[31:0];
            r_sign <= sub_add[32];
            reg_q <= {reg_q[30:0],~sub_add[32]};
            count <= count+1;
            if(count==31)
            	busy <= 0;
        end
    end
end

endmodule
