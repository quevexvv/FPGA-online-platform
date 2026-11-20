`timescale 1ns/1ps
module uart_rx #(parameter integer CLKS_PER_BIT = 434, EVEN_PARITY = 0) (
    input wire clk,
    input wire reset,
    input wire rx,
    output reg [7:0] data = 0,
    output reg valid = 0,
    output reg framing_error = 0,
    output reg parity_error = 0
);
localparam IDLE = 0, START = 1, DATA = 2, STOP = 3, RECOVER = 4, PARITY = 5;
reg [2:0] state = IDLE;
reg rx_meta = 1, rx_sync = 1;
reg [31:0] timer = 0;
reg [2:0] bit_index = 0;
reg [7:0] shift = 0;
reg bad_parity = 0;

// RX is asynchronous; only the second synchronizer stage is sampled.
always @(posedge clk) begin
    rx_meta <= rx;
    rx_sync <= rx_meta;
    valid <= 0;
    framing_error <= 0;
    parity_error <= 0;
    if (reset) begin
        rx_meta <= 1;
        rx_sync <= 1;
        state <= IDLE;
        timer <= 0;
        bit_index <= 0;
        shift <= 0;
        data <= 0;
        bad_parity <= 0;
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
            if (bit_index == 7) state <= EVEN_PARITY ? PARITY : STOP;
            else bit_index <= bit_index + 1'b1;
        end
        PARITY: if (timer != 0) timer <= timer - 1'b1;
        else begin
            bad_parity <= rx_sync ^ (^shift);
            timer <= CLKS_PER_BIT - 1;
            state <= STOP;
        end
        STOP: if (timer != 0) timer <= timer - 1'b1;
        else if (rx_sync) begin
            if (EVEN_PARITY && bad_parity) parity_error <= 1;
            else begin
                data <= shift;
                valid <= 1;
            end
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
