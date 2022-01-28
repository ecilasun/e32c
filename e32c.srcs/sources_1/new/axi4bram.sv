`timescale 1ns / 1ps

module axi4bram(
	input wire aclk,
	input wire aresetn,
    axi4lite.slave axi4if);

axi4litebram64 A4LMemory(
  .s_aclk(aclk),
  .s_aresetn(aresetn),
  .s_axi_awaddr(axi4if.awaddr),    // input wire [31 : 0] s_axi_awaddr
  .s_axi_awvalid(axi4if.awvalid),  // input wire s_axi_awvalid
  .s_axi_awready(axi4if.awready),  // output wire s_axi_awready
  .s_axi_wdata(axi4if.wdata),      // input wire [31 : 0] s_axi_wdata
  .s_axi_wstrb(axi4if.wstrb),      // input wire [3 : 0] s_axi_wstrb
  .s_axi_wvalid(axi4if.wvalid),    // input wire s_axi_wvalid
  .s_axi_wready(axi4if.wready),    // output wire s_axi_wready
  .s_axi_bresp(axi4if.bresp),      // output wire [1 : 0] s_axi_bresp
  .s_axi_bvalid(axi4if.bvalid),    // output wire s_axi_bvalid
  .s_axi_bready(axi4if.bready),    // input wire s_axi_bready
  .s_axi_araddr(axi4if.araddr),    // input wire [31 : 0] s_axi_araddr
  .s_axi_arvalid(axi4if.arvalid),  // input wire s_axi_arvalid
  .s_axi_arready(axi4if.arready),  // output wire s_axi_arready
  .s_axi_rdata(axi4if.rdata),      // output wire [31 : 0] s_axi_rdata
  .s_axi_rresp(axi4if.rresp),      // output wire [1 : 0] s_axi_rresp
  .s_axi_rvalid(axi4if.rvalid),    // output wire s_axi_rvalid
  .s_axi_rready(axi4if.rready)     // input wire s_axi_rready
);

endmodule
