`timescale 1ns / 1ps

module registerfile(
	input wire clk,
	input wire [5:0] rs1,		// Source registers
	input wire [5:0] rs2,
	input wire [5:0] rd,		// Destination register
	input wire we,				// Data write enable
	input wire [31:0] din,		// Data in
	output wire [31:0] dout1,	// Data out
	output wire [31:0] dout2 );

logic [31:0] registers[0:31];

initial begin
	int i;
	for (i=0;i<32;i=i+1) begin
		registers[i] = 32'd0;
	end
end

always @(posedge clk) begin
	if (we && (rd!=0))
		registers[rd] <= din;
end

assign dout1 = registers[rs1];
assign dout2 = registers[rs2];

endmodule
