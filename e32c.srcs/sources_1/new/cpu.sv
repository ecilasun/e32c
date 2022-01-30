`timescale 1ns / 1ps

`include "shared.vh"

// ----------------------------------------------------------------------------
// CPU
// ----------------------------------------------------------------------------

module cpu#(
	parameter int RESETVECTOR = 32'h80000000,
	parameter int HARTID = 32'h00000000
)(
	input wire aclk,
	input wire aresetn,
	axi4lite.master axi4if );

// ----------------------------------------------------------------------------
// Decoded values / Internal states
// ----------------------------------------------------------------------------

logic [31:0] PC = 32'd0;

logic [5:0] rs1 = 6'd0;
logic [5:0] rs2 = 6'd0;
logic [5:0] rd = 6'd0;
logic [6:0] opcode;
logic [2:0] func3;
logic [6:0] func7;
logic [31:0] immed;
logic [3:0] aluop = `alu_none;
logic [2:0] bluop = `blu_none;

// ----------------------------------------------------------------------------
// Register flags
// ----------------------------------------------------------------------------

logic [1:0] regflags[0:31];
initial begin
	int i;
	for (i=0;i<32;i=i+1)
		regflags[i] <= 2'b00; // Register available for r/w by default
end

// ----------------------------------------------------------------------------
// Register file
// ----------------------------------------------------------------------------

logic rwe = 1'b0;
logic [31:0] rdin;
wire [31:0] rval1, rval2;

registerfile IntRegs(
	.clk(aclk),
	.rs1(rs1),
	.rs2(rs2),
	.rd(rd),
	.we(rwe),
	.din(rdin),
	.dout1(rval1),
	.dout2(rval2) );

// ----------------------------------------------------------------------------
// Instruction Fetch
// ----------------------------------------------------------------------------

logic [31:0] resumeaddress = 32'd0;
logic bresume = 1'b0;
logic fetchre = 1'b0;
wire fetchempty, fetchvalid;
wire [63:0] fetchdout;
wire memready;

logic [31:0] busaddress;
logic [31:0] busdin;
logic [3:0] buswe = 4'h0;
logic busre = 1'b0;
wire [31:0] busdout;

fetchunit #(
	.RESETVECTOR(RESETVECTOR),
	.HARTID(HARTID)
) IFETCHLOADSTORE (
	.aclk(aclk),
	.aresetn(aresetn),
	.resume(bresume),
	.resumeaddress(resumeaddress),
	.axi4if(axi4if),
	.fetchre(fetchre),
	.fetchvalid(fetchvalid),
	.fetchempty(fetchempty),
	.fetchdout(fetchdout),
	.busaddress(busaddress),
	.buswe(buswe),
	.busre(busre),
	.busdin(busdin),
	.busdout(busdout),
	.memready(memready) );

// ----------------------------------------------------------------------------
// ALU
// ----------------------------------------------------------------------------

logic aluen = 1'b0;

wire reqalu =	(opcode==`opcode_auipc) |
				(opcode==`opcode_jal) |
				(opcode==`opcode_branch); // these instructions require the first operand to be pc and second one to be the immediate

wire [31:0] aluout;

wire selector =	(opcode==`opcode_jalr) |
				(opcode==`opcode_op_imm) |
				(opcode==`opcode_load) |
				(opcode==`opcode_float_ldw) |
				(opcode==`opcode_float_stw) |
				(opcode==`opcode_store);

arithmeticlogicunit alu(
	.enable(aluen),								// hold high to get a result on next clock
	.aluout(aluout),							// result of calculation
	.func3(func3),								// alu sub-operation code
	.val1(reqalu ? PC : rval1),					// input value 1
	.val2((selector | reqalu) ? immed : rval2),	// input value 2
	.aluop(reqalu ? `alu_add : aluop) );		// alu operation code (also add for jalr for rval1+immed)

// ----------------------------------------------------------------------------
// BLU
// ----------------------------------------------------------------------------

logic bluen = 1'b0;

wire branchout;

branchlogicunit blu(
	.enable(bluen),
	.branchout(branchout),	// high when branch should be taken based on op
	.val1(rval1),			// input value 1
	.val2(rval2),			// input value 2
	.bluop(bluop) );		// comparison operation code

// ----------------------------------------------------------------------------
// Instruction decode
// ----------------------------------------------------------------------------

typedef enum logic [3:0] {INIT, FETCH, DECODE, LOADWAIT, STORE, STOREWAIT, EXEC} exec_state_type;
exec_state_type execstate;

always_comb begin
	if (~aresetn) begin
		//
	end else begin
		rs1 = fetchdout[19:15];
		rs2 = fetchdout[24:20];
		rd = fetchdout[11:7];
		opcode = fetchdout[6:0];
		func3 = fetchdout[14:12];
		func7 = fetchdout[31:25];
	end
end

wire isfpuopcode =	(opcode == `opcode_float_op) |
					(opcode == `opcode_float_ldw) |
					(opcode == `opcode_float_stw) |
					(opcode == `opcode_float_madd) |
					(opcode == `opcode_float_msub) |
					(opcode == `opcode_float_nmsub) |
					(opcode == `opcode_float_nmadd);

wire recordingform = ~((opcode == `opcode_branch) | (opcode == `opcode_store) | isfpuopcode) | ((opcode == `opcode_system) & (|func3));

always_comb begin
	if (~aresetn) begin
		bluop = `blu_none;
	end else begin
		// Branch detection and setup
		case (opcode)
			`opcode_lui, `opcode_auipc: begin immed = {fetchdout[31:12], 12'd0}; bluop = `blu_none; end
			`opcode_float_stw, `opcode_store: begin immed = {{21{fetchdout[31]}}, fetchdout[30:25], fetchdout[11:7]}; bluop = `blu_none; end
			`opcode_op_imm, `opcode_float_ldw, `opcode_load, `opcode_jalr: begin immed = {{21{fetchdout[31]}}, fetchdout[30:20]}; bluop = `blu_none; end
			`opcode_jal: begin immed = {{12{fetchdout[31]}}, fetchdout[19:12], fetchdout[20], fetchdout[30:21], 1'b0}; bluop = `blu_none; end
			`opcode_branch: begin
				immed = {{20{fetchdout[31]}}, fetchdout[7], fetchdout[30:25], fetchdout[11:8], 1'b0};
				case (fetchdout[14:12])
					3'b000: bluop = `blu_eq;
					3'b001: bluop = `blu_ne;
					3'b110: bluop = `blu_lu;
					3'b111: bluop = `blu_geu;
					3'b101: bluop = `blu_ge;
					3'b100: bluop = `blu_l;
					default /*3'b011, 3'b010*/: bluop = `blu_none;
				endcase
			end
			`opcode_system: begin immed = {27'd0, fetchdout[19:15]}; bluop = `blu_none; end
			default: begin immed = 32'd0; bluop = `blu_none; end
		endcase
	end
end

always_comb begin
	if (~aresetn) begin
		aluop = `alu_none;
	end else begin
		// Arithmetic op detection
		case (opcode)
			`opcode_op_imm: begin
				case (fetchdout[14:12])
					3'b000: aluop = `alu_add;
					3'b001: aluop = `alu_sll;
					3'b011: aluop = `alu_sltu;
					3'b010: aluop = `alu_slt;
					3'b110: aluop = `alu_or;
					3'b111: aluop = `alu_and;
					3'b101: aluop = fetchdout[30] ? `alu_sra : `alu_srl;
					3'b100: aluop = `alu_xor;
				endcase
			end
			`opcode_op: begin
				if (fetchdout[25]) begin
					case (fetchdout[14:12])
						3'b000, 3'b001, 3'b010, 3'b011: aluop = `alu_mul;
						3'b100, 3'b101: aluop = `alu_div;
						3'b110, 3'b111: aluop = `alu_rem;
					endcase
				end else begin
					case (fetchdout[14:12])
						3'b000: aluop = fetchdout[30] ? `alu_sub : `alu_add;
						3'b001: aluop = `alu_sll;
						3'b011: aluop = `alu_sltu;
						3'b010: aluop = `alu_slt;
						3'b110: aluop = `alu_or;
						3'b111: aluop = `alu_and;
						3'b101: aluop = fetchdout[30] ? `alu_sra : `alu_srl;
						3'b100: aluop = `alu_xor;
					endcase
				end
			end
			`opcode_jalr: begin
				aluop = `alu_add;
			end
			default: begin
				aluop = `alu_none;
			end
		endcase
	end
end

// ----------------------------------------------------------------------------
// Instruction execute
// ----------------------------------------------------------------------------

always @(posedge aclk) begin
	if (~aresetn) begin
		//
		execstate <= INIT;
	end else begin

		fetchre <= 1'b0;
		bresume <= 1'b0;
		aluen <= 1'b0;
		bluen <= 1'b0;
		buswe <= 4'h0;
		busre <= 1'b0;
		rwe <= 1'b0;

		case (execstate)
			INIT: begin
				// ...
				execstate <= FETCH;
			end

			FETCH: begin
				// Pull
				if (~fetchempty) begin
					fetchre <= 1'b1;
					execstate <= DECODE;
				end
			end

			DECODE: begin
				// Decode
				if (fetchvalid) begin
					aluen <= 1'b1;
					bluen <= 1'b1;

					// To be used for relative addressing or to calculate new branch offset
					PC <= fetchdout[63:32];

					// Memory address to access for load/store
					busaddress <= rval1 + immed;

					// Default return address for load/store stall
					resumeaddress <= fetchdout[63:32] + 32'd4;

					if (opcode == `opcode_load) begin
						busre <= 1'b1;
						execstate <= LOADWAIT;
					end else if (opcode == `opcode_store) begin
						execstate <= STORE;
					end else
						execstate <= EXEC;
				end
			end

			LOADWAIT: begin
				if (memready) begin
					bresume <= 1'b1;
					case (func3)
						3'b000: begin // byte with sign extension
							case (busaddress[1:0])
								2'b11: begin rdin <= {{24{busdout[31]}}, busdout[31:24]}; end
								2'b10: begin rdin <= {{24{busdout[23]}}, busdout[23:16]}; end
								2'b01: begin rdin <= {{24{busdout[15]}}, busdout[15:8]}; end
								2'b00: begin rdin <= {{24{busdout[7]}},  busdout[7:0]}; end
							endcase
						end
						3'b001: begin // word with sign extension
							case (busaddress[1])
								1'b1: begin rdin <= {{16{busdout[31]}}, busdout[31:16]}; end
								1'b0: begin rdin <= {{16{busdout[15]}}, busdout[15:0]}; end
							endcase
						end
						3'b010: begin // dword
							/*if (opcode==`opcode_float_ldw) begin
								frwe <= 1'b1;
								frdin <= busdout;
							end else begin*/
								rdin <= busdout;
							/*end*/
						end
						3'b100: begin // byte with zero extension
							case (busaddress[1:0])
								2'b11: begin rdin <= {24'd0, busdout[31:24]}; end
								2'b10: begin rdin <= {24'd0, busdout[23:16]}; end
								2'b01: begin rdin <= {24'd0, busdout[15:8]}; end
								2'b00: begin rdin <= {24'd0, busdout[7:0]}; end
							endcase
						end
						/*3'b101*/ default: begin // word with zero extension
							case (busaddress[1])
								1'b1: begin rdin <= {16'd0, busdout[31:16]}; end
								1'b0: begin rdin <= {16'd0, busdout[15:0]}; end
							endcase
						end
					endcase
					rwe <= 1'b1;
					execstate <= FETCH;
				end
			end

			STORE: begin
				case(func3)
					3'b000: begin // 8 bit
						busdin <= {rval2[7:0], rval2[7:0], rval2[7:0], rval2[7:0]};
						case (busaddress[1:0])
							2'b11: buswe <= 4'h8;
							2'b10: buswe <= 4'h4;
							2'b01: buswe <= 4'h2;
							2'b00: buswe <= 4'h1;
						endcase
					end
					3'b001: begin // 16 bit
						busdin <= {rval2[15:0], rval2[15:0]};
						case (busaddress[1])
							1'b1: buswe <= 4'hc;
							1'b0: buswe <= 4'h3;
						endcase
					end
					3'b010: begin // 32 bit
						busdin <= /*(opcode==`opcode_float_stw) ? frval2 :*/ rval2;
						buswe <= 4'hf;
					end
					default: begin
						busdin <= 32'd0;
						buswe <= 4'h0;
					end
				endcase
				execstate <= STOREWAIT;
			end

			STOREWAIT: begin
				if (memready) begin
					bresume <= 1'b1;
					execstate <= FETCH;
				end
			end

			EXEC: begin
				// Execute
				case (opcode)
					`opcode_lui: rdin <= immed;
					`opcode_jal, `opcode_jalr, `opcode_branch: rdin <= resumeaddress;
					`opcode_op, `opcode_op_imm, `opcode_auipc: rdin <= /*mwrite ? mout :*/ aluout;
					/*`opcode_system: rdin <= csrval; // TODO: more here
					*/
				endcase

				rwe <= recordingform;

				// Branch address
				case (opcode)
					`opcode_jal, `opcode_jalr: begin resumeaddress <= aluout; bresume <= 1'b1; end
					`opcode_branch: begin resumeaddress <= branchout ? aluout : resumeaddress; bresume <= 1'b1; end
				endcase

				execstate <= FETCH;
			end
		endcase
	end
end

endmodule
