// ------------------------------------------
// Uncompressed opcodes
// ------------------------------------------

`define opcode_op		    7'b0110011
`define opcode_op_imm 	    7'b0010011
`define opcode_lui		    7'b0110111
`define opcode_store	    7'b0100011
`define opcode_load		    7'b0000011
`define opcode_jal		    7'b1101111
`define opcode_jalr		    7'b1100111
`define opcode_branch	    7'b1100011
`define opcode_auipc	    7'b0010111
`define opcode_fence	    7'b0001111
`define opcode_system	    7'b1110011
`define opcode_float_op     7'b1010011
`define opcode_float_ldw    7'b0000111
`define opcode_float_stw    7'b0100111
`define opcode_float_madd   7'b1000011
`define opcode_float_msub   7'b1000111
`define opcode_float_nmsub  7'b1001011
`define opcode_float_nmadd  7'b1001111

// ------------------------------------------
// Decoder one-hot states
// ------------------------------------------

`define o_h_op				17
`define o_h_op_imm			16
`define o_h_lui				15
`define o_h_store			14
`define o_h_load			13
`define o_h_jal				12
`define o_h_jalr			11
`define o_h_branch			10
`define o_h_auipc			9
`define o_h_fence			8
`define o_h_system			7
`define o_h_float_op		6
`define o_h_float_ldw		5
`define o_h_float_stw		4
`define o_h_float_madd		3
`define o_h_float_msub		2
`define o_h_float_nmsub		1
`define o_h_float_nmadd		0

// ------------------------------------------
// ALU
// ------------------------------------------

`define alu_none 		4'd0
`define alu_add 		4'd1
`define alu_sub			4'd2
`define alu_sll			4'd3
`define alu_slt			4'd4
`define alu_sltu		4'd5
`define alu_xor			4'd6
`define alu_srl			4'd7
`define alu_sra			4'd8
`define alu_or			4'd9
`define alu_and			4'd10
// mul/div
`define alu_mul			4'd11
`define alu_div			4'd12
`define alu_rem			4'd13

// ------------------------------------------
// BLU
// ------------------------------------------

`define blu_none		3'd0
`define blu_eq			3'd1
`define blu_ne			3'd2
`define blu_l			3'd3
`define blu_ge			3'd4
`define blu_lu			3'd5
`define blu_geu			3'd6

// ------------------------------------------
// CSR local indices
// ------------------------------------------

`define csr_register_count 16

`define csr_unused		5'd0
`define csr_mstatus		5'd1
`define csr_mie			5'd2
`define csr_mtvec		5'd3
`define csr_mepc		5'd4
`define csr_mcause		5'd5
`define csr_mtval		5'd6
`define csr_mip			5'd7
`define csr_timecmplo	5'd8
`define csr_timecmphi	5'd9
`define csr_cyclelo		5'd10
`define csr_cyclehi		5'd11
`define csr_timelo		5'd12
`define csr_retilo		5'd13
`define csr_timehi		5'd14
`define csr_retihi		5'd15

// ------------------------------------------
// Sub-instructions
// ------------------------------------------

// Flow control
`define f3_beq		3'b000
`define f3_bne		3'b001
`define f3_blt		3'b100
`define f3_bge		3'b101
`define f3_bltu		3'b110
`define f3_bgeu		3'b111

// Logic ops
`define f3_add		3'b000
`define f3_sll		3'b001
`define f3_slt		3'b010
`define f3_sltu		3'b011
`define f3_xor		3'b100
`define f3_sr		3'b101
`define f3_or		3'b110
`define f3_and		3'b111

// Integer math
`define f3_mul		3'b000
`define f3_mulh		3'b001
`define f3_mulhsu	3'b010
`define f3_mulhu	3'b011
`define f3_div		3'b100
`define f3_divu		3'b101
`define f3_rem		3'b110
`define f3_remu		3'b111

// Load type
`define f3_lb		3'b000
`define f3_lh		3'b001
`define f3_lw		3'b010
`define f3_lbu		3'b100
`define f3_lhu		3'b101

// Store type
`define f3_sb		3'b000
`define f3_sh		3'b001
`define f3_sw		3'b010

// Float compare type
`define f3_feq		3'b010
`define f3_flt		3'b001
`define f3_fle		3'b000

// Floating point math
`define f7_fadd        7'b0000000
`define f7_fsub        7'b0000100
`define f7_fmul        7'b0001000
`define f7_fdiv        7'b0001100
`define f7_fsqrt       7'b0101100

// Sign injection
`define f7_fsgnj       7'b0010000
`define f7_fsgnjn      7'b0010000
`define f7_fsgnjx      7'b0010000

// Comparison / classification
`define f7_fmin        7'b0010100
`define f7_fmax        7'b0010100
`define f7_feq         7'b1010000
`define f7_flt         7'b1010000
`define f7_fle         7'b1010000
`define f7_fclass      7'b1110000

// Conversion from/to integer
`define f7_fcvtws      7'b1100000
`define f7_fcvtwus     7'b1100000
`define f7_fcvtsw      7'b1101000
`define f7_fcvtswu     7'b1101000

// Move from/to integer registers
`define f7_fmvxw       7'b1110000
`define f7_fmvwx       7'b1111000
