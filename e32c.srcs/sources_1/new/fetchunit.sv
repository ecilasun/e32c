`timescale 1ns / 1ps

// This is the instruction fetch / memory load / memory store unit.
// It is a combined unit to make bus access easy and to avoid arbitration.

module fetchunit#(
	parameter int RESETVECTOR = 32'h80000000,
	parameter int HARTID = 32'h00000000
)(
	input wire aclk,
	input wire aresetn,
	// Stall recovery (driven by execute unit)
	input wire resume,
	input wire [31:0] resumeaddress,
	// Single bus to memory
	axi4lite.master axi4if,
	// Instruction access (read by execute unit)
	input wire fetchre,
	output wire fetchempty,
	output wire fetchvalid,
	output wire [63:0] fetchdout,
	// Read/Write command access (driven by execute unit during stall)
	input wire [31:0] busaddress,
	input wire [3:0] buswe,
	input wire busre,
	input wire [31:0] busdin,
	output logic [31:0] busdout = 32'd0,
	output logic memready = 1'b0 );

// ----------------------------------------------------------------------------
// Fetch FIFO
// ----------------------------------------------------------------------------

wire fetchfull;
logic [63:0] fetchdin = 64'd0;
logic fetchwe = 1'b0;

fetchoutfifo FetchUnitOut(
	.full(fetchfull),
	.din(fetchdin),
	.wr_en(fetchwe),
	.empty(fetchempty),
	.dout(fetchdout),
	.rd_en(fetchre),
	.valid(fetchvalid),
	.clk(aclk),
	.rst(~aresetn) );

// ----------------------------------------------------------------------------
// Main state machine
// ----------------------------------------------------------------------------

typedef enum logic [3:0] {INIT, FETCH, STALL, READWAIT, MEMREAD, MEMWRITE} fetch_state_type;
fetch_state_type fetchstate;

logic [31:0] PC = RESETVECTOR;

always_ff @(posedge aclk) begin
	if (~aresetn) begin
		fetchstate <= INIT;
	end else begin

		fetchwe <= 1'b0;
		memready <= 1'b0;

		case (fetchstate)
			INIT : begin
				axi4if.awvalid <= 1'b0;
				axi4if.wvalid <= 1'b0;
				axi4if.wstrb <= 4'h0;
				axi4if.wlast <= 1'b1;
				axi4if.arvalid <= 1'b0;
				axi4if.rready <= 1'b0;
				axi4if.bready <= 1'b0;
				fetchstate <= FETCH;
			end

			FETCH : begin
				// Set up read from current address
				axi4if.araddr <= PC;
				axi4if.arvalid <= 1'b1;
				axi4if.rready <= 1'b1;
				fetchstate <= READWAIT; // See if result is available
			end

			READWAIT: begin
				fetchstate <= READWAIT;
				if (axi4if.arready) begin
					axi4if.arvalid <= 1'b0;
				end
				if (axi4if.rvalid && (~fetchfull)) begin
					axi4if.rready <= 1'b0;

					// Store for exec unit
					fetchwe <= 1'b1;
					fetchdin <= {PC, axi4if.rdata};

					// TODO: Handle instuction decompression here (PC will increment by 2 instead for compressed)
					// Advance the PC for next time around (this might get overriden during a branch stall)
					PC <= PC + 32'd4;

					case (axi4if.rdata[6:0])
						`opcode_branch, `opcode_jal, `opcode_jalr,
						`opcode_load, `opcode_float_ldw,
						`opcode_store, `opcode_float_stw: begin
							// Will need to stall now, since we need to calculate next PC
							// or LOAD/STORE data which would clash with memory activity in this unit
							// NOTE: Due to the nature of AXI4Lite, might not need to stall for STORE
							fetchstate <= STALL;
						end
						default: begin
							fetchstate <= FETCH;
						end
					endcase
				end
			end

			STALL: begin
				if (resume) begin
					PC <= resumeaddress;
					fetchstate <= FETCH;
				end else begin
					// Check for any memory access request during stall
					if (busre) begin
						axi4if.araddr <= busaddress;
						axi4if.arvalid <= 1'b1;
						axi4if.rready <= 1'b1;
						fetchstate <= MEMREAD;
					end else if (|buswe) begin
						axi4if.awaddr <= busaddress;
						axi4if.awvalid <= 1'b1;
						axi4if.wvalid <= 1'b1;
						axi4if.bready <= 1'b1;
						axi4if.wstrb <= buswe;
						axi4if.wdata <= busdin;
						fetchstate <= MEMWRITE;
					end else begin
						fetchstate <= STALL;
					end
				end
			end

			MEMREAD: begin
				if (axi4if.arready) begin
					axi4if.arvalid <= 1'b0;
				end
				if (axi4if.rvalid && (~fetchfull)) begin
					axi4if.rready <= 1'b0;
					busdout <= axi4if.rdata;
					memready <= 1'b1;
					fetchstate <= STALL;
				end
			end

			MEMWRITE: begin
				if (axi4if.awready) begin
					axi4if.awvalid <= 1'b0;
				end
				if (axi4if.wready) begin
					axi4if.wvalid <= 1'b0;
					axi4if.wstrb <= 4'h0;
				end
				if (axi4if.bvalid) begin
					memready <= 1'b1;
					axi4if.bready <= 1'b0;
					fetchstate <= STALL;
				end
			end
		endcase
	end
end

endmodule
