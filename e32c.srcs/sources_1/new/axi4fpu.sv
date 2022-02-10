`timescale 1ns / 1ps

module axi4fpu(
	input wire aclk,
	input wire aresetn,
	axi4lite.slave axi4if );

// ----------------------------------------------------------------------------
// FPU
// ----------------------------------------------------------------------------

logic [31:0] frval1 = 32'd0;
logic [31:0] frval2 = 32'd0;
logic [31:0] frval3 = 32'd0;
logic [31:0] rval1 = 32'd0;

//logic [15:0] strobe = {fmaddstrobe, fmsubstrobe, fnmsubstrobe, fnmaddstrobe, faddstrobe, fsubstrobe, fmulstrobe, fdivstrobe, fi2fstrobe, fui2fstrobe, ff2istrobe, ff2uistrobe, fsqrtstrobe, feqstrobe, fltstrobe, flestrobe};
logic [15:0] strobe = 16'd0;

wire fpuresultvalid;
wire [31:0] fpuresult;

floatingpointunit axi4fpudevice(
	.clock(aclk),

	// inputs
	.frval1(frval1),
	.frval2(frval2),
	.frval3(frval3),
	.rval1(rval1), // i2f input

	// operation select strobe
	.fmaddstrobe(strobe[15]),
	.fmsubstrobe(strobe[14]),
	.fnmsubstrobe(strobe[13]),
	.fnmaddstrobe(strobe[12]),
	.faddstrobe(strobe[11]),
	.fsubstrobe(strobe[10]),
	.fmulstrobe(strobe[9]),
	.fdivstrobe(strobe[8]),
	.fi2fstrobe(strobe[7]),
	.fui2fstrobe(strobe[6]),
	.ff2istrobe(strobe[5]),
	.ff2uistrobe(strobe[4]),
	.fsqrtstrobe(strobe[3]),
	.feqstrobe(strobe[2]),
	.fltstrobe(strobe[1]),
	.flestrobe(strobe[0]),

	// output
	.resultvalid(fpuresultvalid),
	.result(fpuresult) );

logic [31:0] fpufifodin;
logic fpufifowe = 1'b0;
logic fpufifore = 1'b0;
wire [31:0] fpufifodout;
wire fpufifofull, fpufifoempty, fpufifovalid;

fpufifo fpuresultfifo (
	.clk(aclk),
	.rst(~aresetn),
	.din(fpufifodin),
	.wr_en(fpufifowe),
	.rd_en(fpufifore),
	.dout(fpufifodout),
	.full(fpufifofull),
	.empty(fpufifoempty),
	.valid(fpufifovalid) );

always @(posedge aclk) begin
	fpufifowe <= 1'b0;
	if (fpuresultvalid & (~fpufifofull)) begin
		fpufifowe <= 1'b1;
		fpufifodin <= fpuresult;
	end
end

// ----------------------------------------------------------------------------
// main state machine
// ----------------------------------------------------------------------------

logic [1:0] waddrstate = 2'b00;
logic [1:0] writestate = 2'b00;
logic [1:0] raddrstate = 2'b00;

always @(posedge aclk) begin
	if (~aresetn) begin
		axi4if.awready <= 1'b1;
	end else begin
		// write address
		case (waddrstate)
			2'b00: begin
				if (axi4if.awvalid /*& cansend*/) begin
					//writeaddress <= axi4if.awaddr;
					axi4if.awready <= 1'b0;
					waddrstate <= 2'b01;
				end
			end
			default/*2'b01*/: begin
				axi4if.awready <= 1'b1;
				waddrstate <= 2'b00;
			end
		endcase
	end
end

logic [2:0] writeslot = 3'd0;

always @(posedge aclk) begin
	if (~aresetn) begin
		axi4if.wready <= 1'b0;
		axi4if.bvalid <= 1'b0;
		axi4if.bresp = 2'b00; // Input OK
	end else begin
		strobe <= 16'd0;
	
		case (writestate)
			2'b00: begin
				if (axi4if.wvalid /*& cansend*/) begin
					// After address is written, expect to read a 5x32 burst of data
					writeslot <= 3'd0;
					//if(axi4if.bready) begin
					frval1 <= axi4if.wdata;
					axi4if.wready <= 1'b1;
					writestate <= 2'b01; //end
				end
			end
			2'b01: begin
				axi4if.wready <= 1'b1;
				if(axi4if.bready) begin
					// This unit expects a burst write
					case (writeslot)
						3'd0: frval2 <= axi4if.wdata;
						3'd1: frval3 <= axi4if.wdata;
						3'd2: rval1 <= axi4if.wdata;
						default /*3'd4*/: strobe <= axi4if.wdata[15:0];// Operation to execute
					endcase
					// Is this the last entry in the write burst?
					if (~axi4if.wlast) begin
						// Increment write slot and wait for more
						writeslot <= writeslot + 3'd1;
						// Done accepting burst data
						axi4if.wready <= 1'b0;
					end else begin
						// Last entry, we're done for now
						axi4if.bvalid <= 1'b1;
						//axi4if.bresp = 2'b00; // Input OK
						writestate <= 2'b10;
					end
				end
			end
			default/*2'b10*/: begin
				axi4if.bvalid <= 1'b0;
				writestate <= 2'b00;
			end
		endcase
	end
end

always @(posedge aclk) begin
	if (~aresetn) begin
		axi4if.arready <= 1'b1;
		axi4if.rvalid <= 1'b0;
		axi4if.rresp <= 2'b00;
		axi4if.rdata <= 32'd0;
	end else begin

		fpufifore <= 1'b0;

		// read address
		case (raddrstate)
			2'b00: begin
				if (axi4if.arvalid) begin
					axi4if.arready <= 1'b0;
					raddrstate <= 2'b01;
				end
			end
			2'b01: begin
				// Any address can be read to retrieve the FPU result
				if (axi4if.rready & (~fpufifoempty)) begin
					fpufifore <= 1'b1;
					raddrstate <= 2'b10; // delay one clock for master to pull down arvalid
				end
			end
			2'b10: begin
				if (fpufifovalid) begin
					axi4if.rdata <= fpufifodout;
					axi4if.rvalid <= 1'b1;
					raddrstate <= 2'b11;
				end
			end
			default/*2'b11*/: begin
				axi4if.rvalid <= 1'b0;
				axi4if.arready <= 1'b1;
				raddrstate <= 2'b00;
			end
		endcase
	end
end

endmodule
