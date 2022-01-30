`timescale 1ns / 1ps

module topmodule(
	input wire sys_clock,
	output wire uart_rxd_out,
	input wire uart_txd_in );

wire baseclock, wallclock, uartbaseclock;
wire resetn;
clockandresetgen ClkGen(
	.sys_clock_i(sys_clock),
	.baseclock(baseclock),
	.wallclock(wallclock),
	.uartbaseclock(uartbaseclock),
	.selfresetn(resetn) );

// Bus interface
axi4lite busif();

axi4devicechain DeviceChain(
	.aclk(baseclock),
	.aresetn(resetn),
	.uartbaseclock(uartbaseclock),
	.uart_rxd_out(uart_rxd_out),
	.uart_txd_in(uart_txd_in),
	.axi4if(busif) );

// CPU
cpu #(
	.RESETVECTOR(32'h80000000),
	.HARTID(0)
) DECODEEXECWBACK (
	.aclk(baseclock),
	.aresetn(resetn),
	.axi4if(busif) );

endmodule

// As general rules:
// - pull one instruction from fifo
// - for load: mark target register L, stash read request into load/store unit (so that first read from this register waits for load result)
// - for store: mark source register S, stash write request into load/store unit (so that attempts to write onto this register wait for store result)
// - for any operation reading from registers, wait for L bit clear
// - for any operation writing to register (not from memory), wait for W bit clear (and abandon any L that wasn't read)
// Wait for destination register to have its W bit clear (we will write to this register, but it has to first flush contents). Reading from a register with its W bit set is OK as the contents are still valid.
// Wait for source register to have its L bit clear (we will read from this register, but it has to complete pending loads). Writing to a register with its L bit set is an overwrite, and might be OK to load again (needs to be checked)
