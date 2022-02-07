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
	.clock(axi4if.aclk),

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

always @(posedge aclk) begin
	if (~aresetn) begin
		//
	end else begin
		strobe <= 16'd0;
	
		case (writestate)
			2'b00: begin
				if (axi4if.wvalid /*& cansend*/) begin
					// Load data into registers and kick
					// the operation once address ...10 is written to
					case (axi4if.awaddr[7:0])
						8'h00: frval1 <= axi4if.wdata;
						8'h04: frval2 <= axi4if.wdata;
						8'h08: frval3 <= axi4if.wdata;
						8'h0C: rval1 <= axi4if.wdata;
						8'h10: strobe <= axi4if.wdata[15:0];
					endcase
					axi4if.wready <= 1'b1;
					writestate <= 2'b01;
				end
			end
			2'b01: begin
				axi4if.wready <= 1'b0;
				if(axi4if.bready) begin
					axi4if.bvalid <= 1'b1;
					axi4if.bresp = 2'b00; // okay
					writestate <= 2'b10;
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
