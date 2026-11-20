`timescale 1ns/1ps
module uart_rx #(parameter integer CLKS_PER_BIT = 434) (
    input wire clk,
    input wire reset,
    input wire rx,
    output reg [7:0] data = 0,
    output reg valid = 0,
    output reg framing_error = 0
);
localparam IDLE = 0, START = 1, DATA = 2, STOP = 3, RECOVER = 4;
reg [2:0] state = IDLE;
reg rx_meta = 1, rx_sync = 1;
reg [31:0] timer = 0;
reg [2:0] bit_index = 0;
reg [7:0] shift = 0;

// RX is asynchronous; only the second synchronizer stage is sampled.
always @(posedge clk) begin
    rx_meta <= rx;
    rx_sync <= rx_meta;
    valid <= 0;
    framing_error <= 0;
    if (reset) begin
        rx_meta <= 1;
        rx_sync <= 1;
        state <= IDLE;
        timer <= 0;
        bit_index <= 0;
        shift <= 0;
        data <= 0;
    end else case (state)
        IDLE: if (!rx_sync) begin
            timer <= CLKS_PER_BIT / 2 - 1;
            state <= START;
        end
        START: if (timer != 0) timer <= timer - 1'b1;
        else if (rx_sync) state <= IDLE;
        else begin
            timer <= CLKS_PER_BIT - 1;
            bit_index <= 0;
            state <= DATA;
        end
        DATA: if (timer != 0) timer <= timer - 1'b1;
        else begin
            shift[bit_index] <= rx_sync;
            timer <= CLKS_PER_BIT - 1;
            if (bit_index == 7) state <= STOP;
            else bit_index <= bit_index + 1'b1;
        end
        STOP: if (timer != 0) timer <= timer - 1'b1;
        else if (rx_sync) begin
            data <= shift;
            valid <= 1;
            state <= IDLE;
        end else begin
            framing_error <= 1;
            state <= RECOVER;
        end
        RECOVER: if (rx_sync) state <= IDLE;
        default: state <= IDLE;
    endcase
end
endmodule
