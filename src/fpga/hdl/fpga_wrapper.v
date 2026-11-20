`timescale 1ns/1ps
module fpga_wrapper #(parameter integer CLKS_PER_BIT = 434, HALF_PERIOD = 25) (
    input wire clk, rx,
    output wire tx,
    output wire [17:0] led
);
reg [3:0] startup = 0;
wire reset = startup != 15;
always @(posedge clk) if (reset) startup <= startup + 1'b1;
wire request, done, dut_clk, dut_reset;
wire [7:0] command;
wire [15:0] argument;
wire [9:0] din;
wire [17:0] dout, snapshot;
uart_service #(.CLKS_PER_BIT(CLKS_PER_BIT)) service (
    .clk(clk), .reset(reset), .rx(rx), .tx(tx), .request(request),
    .command(command), .argument(argument), .done(done), .snapshot(snapshot));
dut_control #(.HALF_PERIOD(HALF_PERIOD)) control (
    .clk(clk), .reset(reset), .request(request), .command(command), .argument(argument),
    .dout(dout), .din(din), .dut_clk(dut_clk), .dut_reset(dut_reset),
    .done(done), .snapshot(snapshot));
student_top student (.clk(dut_clk), .reset(dut_reset), .din(din), .dout(dout));
// C5G LEDR0..9 then LEDG0..7; all verified active high.
assign led = dout;
endmodule
