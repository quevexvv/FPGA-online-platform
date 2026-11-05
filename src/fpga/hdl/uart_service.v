`timescale 1ns/1ps
module uart_service #(parameter integer CLKS_PER_BIT = 434) (
    input wire clk, reset, rx,
    output wire tx, request,
    output wire [7:0] command,
    output wire [15:0] argument,
    input wire done,
    input wire [17:0] snapshot
);
wire [7:0] rx_data, tx_data;
wire rx_valid, framing_error, tx_valid, tx_ready, tx_busy;
uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) receiver (
    .clk(clk), .reset(reset), .rx(rx), .data(rx_data),
    .valid(rx_valid), .framing_error(framing_error));
uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) transmitter (
    .clk(clk), .reset(reset), .tx(tx), .data(tx_data),
    .valid(tx_valid), .ready(tx_ready), .busy(tx_busy));
uart_commands #(.GAP_TICKS(CLKS_PER_BIT * 20)) commands (
    .clk(clk), .reset(reset), .rx_data(rx_data), .rx_valid(rx_valid),
    .framing_error(framing_error), .tx_data(tx_data), .tx_valid(tx_valid),
    .tx_ready(tx_ready), .tx_busy(tx_busy), .request(request),
    .command(command), .argument(argument), .done(done), .snapshot(snapshot));
endmodule
