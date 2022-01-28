`timescale 1ns / 1ps

module simtop(

    );

logic sys_clock;

initial begin
	sys_clock = 1'b0;
end

wire uart_rxd_out;
wire uart_txd_in = 1'b1;

topmodule topinst(
	.sys_clock(sys_clock),
	.uart_rxd_out(uart_rxd_out),
	.uart_txd_in(uart_txd_in) );

always #5 sys_clock = ~sys_clock;

endmodule
