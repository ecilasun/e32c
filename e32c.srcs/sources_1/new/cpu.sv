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
logic [31:0] adjacentPC = 32'd0;

logic [4:0] rs1 = 5'd0;
logic [4:0] rs2 = 5'd0;
logic [4:0] rs3 = 5'd0;
logic [4:0] rd = 5'd0;
logic [6:0] opcode;
logic [2:0] func3;
logic [6:0] func7;
logic [31:0] immed;
logic [3:0] aluop = `alu_none;
logic [2:0] bluop = `blu_none;

// ----------------------------------------------------------------------------
// Register flags
// ----------------------------------------------------------------------------

// WRITEPENDING  READPENDING
//            0            0
logic [1:0] regflags[0:31];

initial begin
	int i;
	for (i=0; i<32; i=i+1)
		regflags[i] <= 2'b00;
end

// ----------------------------------------------------------------------------
// Register files
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

logic frwe = 1'b0;
logic [31:0] frdin = 32'd0;
wire [31:0] frval1, frval2, frval3;

floatregisterfile FloatRegs(
	.clock(aclk),
	.rs1(rs1),
	.rs2(rs2),
	.rs3(rs3),
	.rd(rd),
	.wren(frwe),
	.datain(frdin),
	.rval1(frval1),
	.rval2(frval2),
	.rval3(frval3) );

// ----------------------------------------------------------------------------
// Instruction Fetch
// ----------------------------------------------------------------------------

logic [31:0] resumeaddress = 32'd0;
logic bresume = 1'b0;
logic fetchre = 1'b0;
wire fetchempty, fetchvalid;
wire [63:0] fetchdout;
wire memready, writeready;

logic [31:0] busaddress = 32'd0;
logic [31:0] busdin = 32'd0;
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
	.memready(memready),
	.writeready(writeready) );

// ----------------------------------------------------------------------------
// ALU
// ----------------------------------------------------------------------------

logic logicen = 1'b0;

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

arithmeticlogicunit ALU(
	.enable(logicen),							// hold high to get a result on next clock
	.aluout(aluout),							// result of calculation
	.func3(func3),								// alu sub-operation code
	.val1(reqalu ? PC : rval1),					// input value 1
	.val2((selector | reqalu) ? immed : rval2),	// input value 2
	.aluop(reqalu ? `alu_add : aluop) );		// alu operation code (also add for jalr for rval1+immed)

// ----------------------------------------------------------------------------
// BLU
// ----------------------------------------------------------------------------

wire branchout;

branchlogicunit BLU(
	.enable(logicen),
	.branchout(branchout),	// high when branch should be taken based on op
	.val1(rval1),			// input value 1
	.val2(rval2),			// input value 2
	.bluop(bluop) );		// comparison operation code

// ----------------------------------------------------------------------------
// Instruction decode
// ----------------------------------------------------------------------------

typedef enum logic [3:0] {INIT, FETCH, DECODE, LOADWAIT, STORE, IMATHSTALL, FPUOP, FLOATMATHSTALL, FUSEDMATHSTALL, WRITESTALL, EXEC} exec_state_type;
exec_state_type execstate;

always_comb begin
	if (~aresetn) begin
		//
	end else begin
		rs1 = fetchdout[19:15];
		rs2 = fetchdout[24:20];
		rs3 = fetchdout[31:27];
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

// -----------------------------------------------------------------------
// Integer math (mul/div)
// -----------------------------------------------------------------------

wire mulbusy, divbusy, divbusyu;
wire [31:0] product;
wire [31:0] quotient;
wire [31:0] quotientu;
wire [31:0] remainder;
wire [31:0] remainderu;

logic mulstrobe = 1'b0;
logic divstrobe = 1'b0;
logic divustrobe = 1'b0;

singedunsignedmultiplier MulIntUInt(
    .clk(aclk),
    .resetn(aresetn),
    .start(mulstrobe),
    .busy(mulbusy),          // calculation in progress
    .func3(func3),
    .multiplicand(rval1),
    .multiplier(rval2),
    .product(product) );

unsignedintegerdivider DivUInt(
	.clk(aclk),
	.resetn(aresetn),
	.start(divustrobe),		// start signal
	.busy(divbusyu),		// calculation in progress
	.dividend(rval1),		// dividend
	.divisor(rval2),		// divisor
	.quotient(quotientu),	// result: quotient
	.remainder(remainderu)	// result: remainer
);

signedintegerdivider DivInt(
	.clk(aclk),
	.resetn(aresetn),
	.start(divstrobe),		// start signal
	.busy(divbusy),			// calculation in progress
	.dividend(rval1),		// dividend
	.divisor(rval2),		// divisor
	.quotient(quotient),	// result: quotient
	.remainder(remainder)	// result: remainder
);

// Status
wire imathbusy = divbusy | divbusyu | mulbusy | mulstrobe | divstrobe | divustrobe;

// ------------------------------------------------------------------------------------
// Floating point math
// ------------------------------------------------------------------------------------

logic fmaddstrobe = 1'b0;
logic fmsubstrobe = 1'b0;
logic fnmsubstrobe = 1'b0;
logic fnmaddstrobe = 1'b0;
logic faddstrobe = 1'b0;
logic fsubstrobe = 1'b0;
logic fmulstrobe = 1'b0;
logic fdivstrobe = 1'b0;
logic fi2fstrobe = 1'b0;
logic fui2fstrobe = 1'b0;
logic ff2istrobe = 1'b0;
logic ff2uistrobe = 1'b0;
logic fsqrtstrobe = 1'b0;
logic feqstrobe = 1'b0;
logic fltstrobe = 1'b0;
logic flestrobe = 1'b0;

wire fpuresultvalid;
wire [31:0] fpuresult;

floatingpointunit FPU(
	.clock(aclk),

	// inputs
	.frval1(frval1),
	.frval2(frval2),
	.frval3(frval3),
	.rval1(rval1), // i2f input

	// operation select strobe
	.fmaddstrobe(fmaddstrobe),
	.fmsubstrobe(fmsubstrobe),
	.fnmsubstrobe(fnmsubstrobe),
	.fnmaddstrobe(fnmaddstrobe),
	.faddstrobe(faddstrobe),
	.fsubstrobe(fsubstrobe),
	.fmulstrobe(fmulstrobe),
	.fdivstrobe(fdivstrobe),
	.fi2fstrobe(fi2fstrobe),
	.fui2fstrobe(fui2fstrobe),
	.ff2istrobe(ff2istrobe),
	.ff2uistrobe(ff2uistrobe),
	.fsqrtstrobe(fsqrtstrobe),
	.feqstrobe(feqstrobe),
	.fltstrobe(fltstrobe),
	.flestrobe(flestrobe),

	// output
	.resultvalid(fpuresultvalid),
	.result(fpuresult) );

// ----------------------------------------------------------------------------
// LOAD/STORE bus address generation / PC extraction / STORE setup
// ----------------------------------------------------------------------------

logic [3:0] wstrobe = 4'h0;
logic [31:0] wdin = 32'd0;
always_comb begin
	if (~aresetn) begin
		// 
	end else begin
		case(execstate)
			FETCH: begin
				if (~fetchempty) begin
					fetchre = 1'b1;
				end
			end

			DECODE: begin
				fetchre = 1'b0;
				if (fetchvalid) begin
					// To be used for relative addressing or to calculate new branch offset
					PC = fetchdout[63:32];
			
					// Memory address to access for load/store
					busaddress = rval1 + immed;
	
					if ((opcode == `opcode_store) | (opcode == `opcode_float_stw)) begin
						// NOTE: We do not need to wait for memready here since the write can happen
						// by itself, as long as the order of memory operations do not change from our view.
						case(func3)
							`f3_sb: begin // 8 bit
								wdin = {rval2[7:0], rval2[7:0], rval2[7:0], rval2[7:0]};
								case (busaddress[1:0])
									2'b11: wstrobe = 4'h8;
									2'b10: wstrobe = 4'h4;
									2'b01: wstrobe = 4'h2;
									2'b00: wstrobe = 4'h1;
								endcase
							end
							`f3_sh: begin // 16 bit
								wdin = {rval2[15:0], rval2[15:0]};
								case (busaddress[1])
									1'b1: wstrobe = 4'hc;
									1'b0: wstrobe = 4'h3;
								endcase
							end
							default /*`f3_sw*/: begin // 32 bit
								wdin = (opcode==`opcode_float_stw) ? frval2 : rval2;
								wstrobe = 4'hf;
							end
						endcase
					end
				end
			end

			default: begin
				fetchre = 1'b0;
			end

		endcase
	end
end

// ----------------------------------------------------------------------------
// Instruction execute
// ----------------------------------------------------------------------------

wire mulop = (aluop == `alu_mul);
wire divop = ((aluop == `alu_div) & (func3==`f3_div)) | ((aluop == `alu_rem) & (func3 == `f3_rem));
wire divuop = ((aluop == `alu_div) & (func3==`f3_divu)) | ((aluop == `alu_rem) & (func3 == `f3_remu));

wire fmaddop = (opcode == `opcode_float_madd);
wire fmsubop = (opcode == `opcode_float_msub);
wire fnmsubop = (opcode == `opcode_float_nmsub);
wire fnmaddop = (opcode == `opcode_float_nmadd);

always @(posedge aclk) begin
	if (~aresetn) begin
		//
		execstate <= INIT;
	end else begin
		bresume <= 1'b0;
		logicen <= 1'b0;
		buswe <= 4'h0;
		busre <= 1'b0;
		rwe <= 1'b0;
		frwe <= 1'b0;
		mulstrobe <= 1'b0;
		divstrobe <= 1'b0;
		divustrobe <= 1'b0;

		fmaddstrobe <= 1'b0;
		fmsubstrobe <= 1'b0;
		fnmsubstrobe <= 1'b0;
		fnmaddstrobe <= 1'b0;
		faddstrobe <= 1'b0;
		fsubstrobe <= 1'b0;
		fmulstrobe <= 1'b0;
		fdivstrobe <= 1'b0;
		fi2fstrobe <= 1'b0;
		fui2fstrobe <= 1'b0;
		ff2istrobe <= 1'b0;
		ff2uistrobe <= 1'b0;
		fsqrtstrobe <= 1'b0;
		feqstrobe <= 1'b0;
		fltstrobe <= 1'b0;
		flestrobe <= 1'b0;

		case (execstate)
			INIT: begin
				execstate <= FETCH;
			end

			FETCH: begin
				// Pull
				if (~fetchempty) begin
					execstate <= DECODE;
				end
			end

			DECODE: begin
				// Decode
				if (fetchvalid) begin
					logicen <= 1'b1;

					// Default return address for load/store stall
					adjacentPC <= PC + 32'd4;

					if (fmaddop | fmsubop | fnmsubop | fnmaddop) begin
						fmaddstrobe <= fmaddop;
						fmsubstrobe <= fmsubop;
						fnmsubstrobe <= fnmsubop;
						fnmaddstrobe <= fnmaddop;
						execstate <= FUSEDMATHSTALL;
					end else if (opcode == `opcode_float_op) begin
						execstate <= FPUOP;
					end else if ((opcode == `opcode_load) | (opcode == `opcode_float_ldw)) begin
						busre <= 1'b1;
						execstate <= LOADWAIT;
					end else if ((opcode == `opcode_store) | (opcode == `opcode_float_stw)) begin
						execstate <= WRITESTALL;
					end else begin
						mulstrobe <= mulop;
						divstrobe <= divop;
						divustrobe <= divuop;
						execstate <= (mulop | divop | divuop) ? IMATHSTALL : EXEC;
					end
				end
			end

			FUSEDMATHSTALL: begin
				if (fpuresultvalid) begin
					frwe <= 1'b1;
					frdin <= fpuresult;
					execstate <= FETCH;
				end else begin
					execstate <= FUSEDMATHSTALL;
				end
			end

			FPUOP: begin
				case (func7)
					`f7_fsgnj: begin
						frwe <= 1'b1;
						case(func3)
							3'b000: frdin <= {frval2[31], frval1[30:0]}; // fsgnj
							3'b001: frdin <= {~frval2[31], frval1[30:0]}; // fsgnjn
							3'b010: frdin <= {frval1[31]^frval2[31], frval1[30:0]}; // fsgnjx
						endcase
						execstate <= FETCH;
					end
					`f7_fmvxw: begin
						rwe <= 1'b1;
						if (func3 == 3'b000)
							rdin <= frval1; // fmvxw
						else
							rdin <= 32'd0; // fclass todo: classify the float
						execstate <= FETCH;
					end
					`f7_fmvwx: begin
						frwe <= 1'b1;
						frdin <= rval1;
						execstate <= FETCH;
					end
					default: begin
						faddstrobe <= (func7 == `f7_fadd);
						fsubstrobe <= (func7 == `f7_fsub);
						fmulstrobe <= (func7 == `f7_fmul);
						fdivstrobe <= (func7 == `f7_fdiv);
						fi2fstrobe <= (func7 == `f7_fcvtsw) & (rs2==5'b00000); // Signed
						fui2fstrobe <= (func7 == `f7_fcvtsw) & (rs2==5'b00001); // Unsigned
						ff2istrobe <= (func7 == `f7_fcvtws) & (rs2==5'b00000); // Signed
						ff2uistrobe <= (func7 == `f7_fcvtws) & (rs2==5'b00001); // Unsigned
						fsqrtstrobe <= (func7 == `f7_fsqrt);
						feqstrobe <= (func7==`f7_feq) & (func3==`f3_feq);
						fltstrobe <= ((func7==`f7_feq) & (func3==`f3_flt)) | (func7==`f7_fmax); // min/max same as flt
						flestrobe <= (func7==`f7_feq) & (func3==`f3_fle);
						execstate <= FLOATMATHSTALL;
					end
				endcase
			end

			FLOATMATHSTALL: begin
				if (fpuresultvalid) begin
					case (func7)
						`f7_fcvtws: begin
							rwe <= 1'b1;
							rdin <= fpuresult;
						end
						`f7_feq: begin
							rwe <= 1'b1;
							rdin <= {31'd0, fpuresult[0]};
						end
						`f7_fmax: begin
							frwe <= 1'b1;
							if (func3==3'b000) // fmin
								frdin <= fpuresult[0] ? frval1 : frval2;
							else // fmax
								frdin <= fpuresult[0] ? frval2 : frval1;
						end
						default /*add/sub/mul/div/sqrt/cvtsw*/: begin
							frwe <= 1'b1;
							frdin <= fpuresult;
						end
					endcase
					execstate <= FETCH;
				end else begin
					execstate <= FLOATMATHSTALL;
				end
			end

			WRITESTALL: begin
				if (writeready) begin
					busdin <= wdin;
					buswe <= wstrobe;
					execstate <= FETCH;
				end else
					execstate <= WRITESTALL;
			end

			IMATHSTALL: begin
				if (~imathbusy) begin
					case (aluop)
						`alu_div: begin
							rdin <= (func3==`f3_div) ? quotient : quotientu;
						end
						`alu_rem: begin
							rdin <= (func3==`f3_rem) ? remainder : remainderu;
						end
						default /*`alu_mul*/: begin
							rdin <= product;
						end
					endcase
					rwe <= 1'b1;
					execstate <= FETCH;
				end else begin
					execstate <= IMATHSTALL;
				end
			end

			LOADWAIT: begin
				if (memready) begin
					rwe <= 1'b0;
					frwe <= 1'b0;
					case (func3)
						`f3_lb: begin // byte with sign extension
							case (busaddress[1:0])
								2'b11: begin rdin <= {{24{busdout[31]}}, busdout[31:24]}; end
								2'b10: begin rdin <= {{24{busdout[23]}}, busdout[23:16]}; end
								2'b01: begin rdin <= {{24{busdout[15]}}, busdout[15:8]}; end
								2'b00: begin rdin <= {{24{busdout[7]}},  busdout[7:0]}; end
							endcase
							rwe <= 1'b1;
						end
						`f3_lh: begin // word with sign extension
							case (busaddress[1])
								1'b1: begin rdin <= {{16{busdout[31]}}, busdout[31:16]}; end
								1'b0: begin rdin <= {{16{busdout[15]}}, busdout[15:0]}; end
							endcase
							rwe <= 1'b1;
						end
						`f3_lw: begin // dword
							if (opcode==`opcode_float_ldw) begin
								frdin <= busdout;
								frwe <= 1'b1;
							end else begin
								rdin <= busdout;
								rwe <= 1'b1;
							end
						end
						`f3_lbu: begin // byte with zero extension
							case (busaddress[1:0])
								2'b11: begin rdin <= {24'd0, busdout[31:24]}; end
								2'b10: begin rdin <= {24'd0, busdout[23:16]}; end
								2'b01: begin rdin <= {24'd0, busdout[15:8]}; end
								2'b00: begin rdin <= {24'd0, busdout[7:0]}; end
							endcase
							rwe <= 1'b1;
						end
						default /*`f3_lhu*/: begin // word with zero extension
							case (busaddress[1])
								1'b1: begin rdin <= {16'd0, busdout[31:16]}; end
								1'b0: begin rdin <= {16'd0, busdout[15:0]}; end
							endcase
							rwe <= 1'b1;
						end
					endcase
					execstate <= FETCH;
				end
			end

			default /*EXEC*/: begin
				// Execute
				case (opcode)
					`opcode_lui: rdin <= immed;
					`opcode_jal, `opcode_jalr, `opcode_branch: rdin <= adjacentPC;
					`opcode_op, `opcode_op_imm, `opcode_auipc: rdin <= aluout;
					/*`opcode_system: rdin <= csrval; // TODO: more here
					*/
				endcase

				rwe <= recordingform;

				// Branch address
				case (opcode)
					`opcode_jal, `opcode_jalr: begin resumeaddress <= aluout; bresume <= 1'b1; end
					`opcode_branch: begin resumeaddress <= branchout ? aluout : adjacentPC; bresume <= 1'b1; end
				endcase

				execstate <= FETCH;
			end
		endcase
	end
end

endmodule
