`timescale 1ns / 1ps

module clockandresetgen(
	input wire sys_clock_i,
	output wire baseclock,
	output wire wallclock,
	output wire uartbaseclock,
	output logic selfresetn );

wire centralclocklocked, peripheralclocklocked;//, ddr3clklocked, videoclklocked;

centralclockgen centralclock(
	.clk_in1(sys_clock_i),
	.baseclock(baseclock),
	.wallclock(wallclock),
	.locked(centralclocklocked) );

peripheralclocks miscclock(
	.clk_in1(sys_clock_i),
	.uartbaseclock(uartbaseclock),
	.locked(peripheralclocklocked) );

/*ddr3clk ddr3memoryclock(
	.clk_in1(sys_clock_i),
	.ddr3sys(clk_sys_i),
	.ddr3ref(clk_ref_i),
	.locked(ddr3clklocked) );

videoclocks graphicsclock(
	.clk_in1(sys_clock_i),
	.gpubaseclock(gpubaseclock),
	.pixelclock(pixelclock),
	.videoclock(videoclock),
	.locked(videoclklocked) );*/

// hold reset until clocks are locked
//wire internalreset = ~(centralclocklocked & ddr3clklocked & videoclklocked);
wire internalreset = ~(centralclocklocked & peripheralclocklocked);

// delayed reset post-clock-lock
logic [3:0] resetcountdown = 4'hf;
always @(posedge wallclock) begin // using slowest clock
	if (internalreset) begin
		resetcountdown <= 4'hf;
		selfresetn <= 1'b0;
	end else begin
		if (/*busready &&*/ (resetcountdown == 4'h0))
			selfresetn <= 1'b1;
		else
			resetcountdown <= resetcountdown - 4'h1;
	end
end

endmodule
