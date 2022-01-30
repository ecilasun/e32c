`timescale 1ns / 1ps

`include "shared.vh"

module decoder(
	input wire enable,
	input wire [31:0] instruction,				// raw input instruction
	output logic [17:0] instronehotout = 18'd0,	// current instruction class
	output logic isrecordingform = 1'b0,		// high when we can save result to register
	output logic [3:0] aluop = 4'h0,			// current alu op
	output logic [2:0] bluop = 3'h0,			// current blu op
	output logic [2:0] func3 = 3'd0,			// sub-instruction
	output logic [6:0] func7 = 7'd0,			// sub-instruction
	output logic [11:0] func12 = 12'd0,			// sub-instruction
	output logic [4:0] rs1 = 5'd0,				// source register one
	output logic [4:0] rs2 = 5'd0,				// source register two
	output logic [4:0] rs3 = 5'd0,				// used by fused multiplyadd/sub
	output logic [4:0] rd = 5'd0,				// destination register
	output logic [4:0] csrindex,				// index of selected csr register
	output logic [31:0] immed = 32'd0,			// unpacked immediate integer value
	output logic selectimmedasrval2 = 1'b0		// select rval2 or unpacked integer during exec
);

wire [18:0] instronehot = {
	instruction[6:0]==`opcode_op ? 1'b1:1'b0,
	instruction[6:0]==`opcode_op_imm ? 1'b1:1'b0,
	instruction[6:0]==`opcode_lui ? 1'b1:1'b0,
	instruction[6:0]==`opcode_store ? 1'b1:1'b0,
	instruction[6:0]==`opcode_load ? 1'b1:1'b0,
	instruction[6:0]==`opcode_jal ? 1'b1:1'b0,
	instruction[6:0]==`opcode_jalr ? 1'b1:1'b0,
	instruction[6:0]==`opcode_branch ? 1'b1:1'b0,
	instruction[6:0]==`opcode_auipc ? 1'b1:1'b0,
	instruction[6:0]==`opcode_fence ? 1'b1:1'b0,
	instruction[6:0]==`opcode_system ? 1'b1:1'b0,
	instruction[6:0]==`opcode_float_op ? 1'b1:1'b0,
	instruction[6:0]==`opcode_float_ldw ? 1'b1:1'b0,
	instruction[6:0]==`opcode_float_stw ? 1'b1:1'b0,
	instruction[6:0]==`opcode_float_madd ? 1'b1:1'b0,
	instruction[6:0]==`opcode_float_msub ? 1'b1:1'b0,
	instruction[6:0]==`opcode_float_nmsub ? 1'b1:1'b0,
	instruction[6:0]==`opcode_float_nmadd ? 1'b1:1'b0 };

//11:10 -> r/w mode
//9:8 -> lowest privilege level allowed
always_comb begin
	case ({instruction[31:25], instruction[24:20]})
		default: csrindex = `csr_unused;	// illegal instruction exception
		
		//12'hf15: csrindex = `csr_unused;	// mconfigptr, defaults to zero, no exception

		12'h300: csrindex = `csr_mstatus;	// r/w
		12'h304: csrindex = `csr_mie;		// r/w
		12'h305: csrindex = `csr_mtvec;		// r/w [1:0]==2'b00->direct, ==2'b01->vectored
		12'h341: csrindex = `csr_mepc;		// r/w [1:0] always 2'b00 (or [0] always 1'b0)
		12'h342: csrindex = `csr_mcause;	// r/w
		12'h343: csrindex = `csr_mtval;		// r/w excpt specific info such as faulty instruction
		12'h344: csrindex = `csr_mip;		// r/w
		
		//12'h340: scratch register for machine trap mscratch
		//12'h301: isa / extension type misa
		//12'hf14: hardware thread id hartid

		12'h800: csrindex = `csr_timecmplo;	// r/w
		12'h801: csrindex = `csr_timecmphi;	// r/w

		12'hc00,
		12'hb00: csrindex = `csr_cyclelo;	// r/w
		12'hc80,
		12'hb80: csrindex = `csr_cyclehi;	// r/w
		12'hc02,
		12'hb02: csrindex = `csr_retilo;	// r
		12'hc82,
		12'hb82: csrindex = `csr_retihi;	// r

		12'hc01: csrindex = `csr_timelo;	// r
		12'hc81: csrindex = `csr_timehi;	// r

		//12'h7b0: debug control and status register dcsr
		//12'h7b1: debug pc dpc
		//12'h7b2: debug scratch register dscratch0
		//12'h7b3: debug scratch register dscratch1
	endcase
end

// immed vs rval2 selector
wire selector = instronehot[`o_h_jalr] | instronehot[`o_h_op_imm] | instronehot[`o_h_load] | instronehot[`o_h_float_ldw] | instronehot[`o_h_float_stw] | instronehot[`o_h_store];
// every instruction except sys:3'b000, branch, fpu ops and store are recoding form
// i.e. not (branch or store) or (sys and at least one bit set)
wire isfpuopcode = 
	instronehot[`o_h_float_op] |
	instronehot[`o_h_float_ldw] |
	instronehot[`o_h_float_stw] |
	instronehot[`o_h_float_madd] |
	instronehot[`o_h_float_msub] |
	instronehot[`o_h_float_nmsub] |
	instronehot[`o_h_float_nmadd];
wire recording = ~(instronehot[`o_h_branch] | instronehot[`o_h_store] | isfpuopcode) | (instronehot[`o_h_system] & (|func3));

// source/destination register indices
wire [4:0] src1 = instruction[19:15];
wire [4:0] src2 = instruction[24:20];
wire [4:0] src3 = instruction[31:27];
wire [4:0] dest = instruction[11:7];

// sub-functions
wire [2:0] f3 = instruction[14:12];
wire [6:0] f7 = instruction[31:25];
wire [11:0] f12 = instruction[31:20];
wire mathopsel = instruction[30];

// shift in decoded values
always_comb begin
	if (enable) begin
		rs1 = src1;
		rs2 = src2;
		rs3 = src3;
		rd = dest;
		func3 = f3;
		func7 = f7;
		func12 = f12;
		instronehotout = instronehot;
		selectimmedasrval2 = selector;	// use rval2 or immed
		isrecordingform = recording;	// everything except branches and store records result into rd
	end
end

// work out alu op
always_comb begin
	if (enable) begin
		case (1'b1)
			instronehot[`o_h_op]: begin
				if (instruction[25]) begin
					unique case (instruction[14:12])
						3'b000, 3'b001, 3'b010, 3'b011: aluop = `alu_mul;
						3'b100, 3'b101: aluop = `alu_div;
						3'b110, 3'b111: aluop = `alu_rem;
					endcase
				end else begin
					unique case (instruction[14:12])
						3'b000: aluop = instronehot[`o_h_op_imm] ? `alu_add : (mathopsel ? `alu_sub : `alu_add);
						3'b001: aluop = `alu_sll;
						3'b011: aluop = `alu_sltu;
						3'b010: aluop = `alu_slt;
						3'b110: aluop = `alu_or;
						3'b111: aluop = `alu_and;
						3'b101: aluop = mathopsel ? `alu_sra : `alu_srl;
						3'b100: aluop = `alu_xor;
					endcase
				end
			end

			instronehot[`o_h_op_imm]: begin
				unique case (instruction[14:12])
					3'b000: aluop = instronehot[`o_h_op_imm] ? `alu_add : (mathopsel ? `alu_sub : `alu_add);
					3'b001: aluop = `alu_sll;
					3'b011: aluop = `alu_sltu;
					3'b010: aluop = `alu_slt;
					3'b110: aluop = `alu_or;
					3'b111: aluop = `alu_and;
					3'b101: aluop = mathopsel ? `alu_sra : `alu_srl;
					3'b100: aluop = `alu_xor;
				endcase
			end
			
			instronehot[`o_h_jalr]: begin
				aluop = `alu_add;
			end
	
			default: begin
				aluop = `alu_none;
			end
		endcase
	end
end

// work out blu op
always_comb begin
	if (enable) begin
		case (1'b1)
			instronehot[`o_h_branch]: begin
				unique case (instruction[14:12])
					3'b000: bluop = `blu_eq;
					3'b001: bluop = `blu_ne;
					3'b011: bluop = `blu_none;
					3'b010: bluop = `blu_none;
					3'b110: bluop = `blu_lu;
					3'b111: bluop = `blu_geu;
					3'b101: bluop = `blu_ge;
					3'b100: bluop = `blu_l;
				endcase
			end
	
			default: begin
				bluop = `blu_none;
			end
		endcase
	end
end

// work out immediate value
always_comb begin
	if (enable) begin
		case (1'b1)
			default: /*instronehot[`o_h_lui], instronehot[`o_h_auipc]:*/ begin	
				immed = {instruction[31:12], 12'd0};
			end

			instronehot[`o_h_float_stw], instronehot[`o_h_store]: begin
				immed = {{21{instruction[31]}}, instruction[30:25], instruction[11:7]};
			end

			instronehot[`o_h_op_imm], instronehot[`o_h_float_ldw], instronehot[`o_h_load], instronehot[`o_h_jalr]: begin
				immed = {{21{instruction[31]}}, instruction[30:20]};
			end

			instronehot[`o_h_jal]: begin
				immed = {{12{instruction[31]}}, instruction[19:12], instruction[20], instruction[30:21], 1'b0};
			end

			instronehot[`o_h_branch]: begin
				immed = {{20{instruction[31]}}, instruction[7], instruction[30:25], instruction[11:8], 1'b0};
			end

			instronehot[`o_h_system]: begin
				immed = {27'd0, instruction[19:15]};
			end
		endcase
	end
end

endmodule
