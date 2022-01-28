// AXI4-Lite

interface axi4lite ();

	logic [31:0] awaddr;
	logic awvalid;
	logic awready;

	// write data channel signals
	logic [31:0] wdata;
	logic [3:0] wstrb;
	logic wlast;
	logic wvalid;
	logic wready;

	// write response channel signals
	logic [1:0] bresp; // 00:okay 01:exokay 10:slverr 11:decerr
	logic bvalid;
	logic bready;

	// read address channel signals
	logic [31:0] araddr;
	logic arvalid;
	logic arready;

	// read data channel signals
	logic [31:0] rdata;
	logic [1:0] rresp; // 00:okay 01:exokay 10:slverr 11:decerr
	logic rlast;
	logic rvalid;
	logic rready;

	modport master(
		output awaddr, awvalid, input awready,
		output wdata, wstrb, wlast, wvalid, input wready,
		input  bresp, bvalid, output bready,
		output araddr, arvalid, input arready,
		input rdata, rresp, rlast, rvalid, output rready );

	modport slave(
		input awaddr, awvalid, output awready,
		input wdata, wstrb, wlast, wvalid, output wready,
		output bresp, bvalid, input bready,
		input araddr, arvalid, output arready,
		output rdata, rresp, rlast, rvalid, input rready );

endinterface




