`timescale 1ns/1ps
module uart_tx #(parameter integer CLKS_PER_BIT = 434, EVEN_PARITY = 0) (
    input wire clk,
    input wire reset,
    input wire [7:0] data,
    input wire valid,
    output wire ready,
    output wire tx,
    output reg busy = 0
);
localparam FRAME_BITS = EVEN_PARITY ? 11 : 10;
reg [FRAME_BITS-1:0] shift = {FRAME_BITS{1'b1}};
reg [31:0] timer = 0;
reg [3:0] bit_index = 0;
assign ready = !busy && !reset;
assign tx = shift[0];

always @(posedge clk) begin
    if (reset) begin
        shift <= {FRAME_BITS{1'b1}};
        timer <= 0;
        bit_index <= 0;
        busy <= 0;
    end else if (!busy) begin
        if (valid) begin
            // Capture the whole byte before driving the start bit.
            if (EVEN_PARITY) shift <= {1'b1, ^data, data, 1'b0};
            else shift <= {1'b1, data, 1'b0};
            timer <= CLKS_PER_BIT - 1;
            bit_index <= 0;
            busy <= 1;
        end
    end else if (timer != 0) timer <= timer - 1'b1;
    else if (bit_index == FRAME_BITS - 1) begin
        shift <= {FRAME_BITS{1'b1}};
        busy <= 0;
    end else begin
        shift <= {1'b1, shift[FRAME_BITS-1:1]};
        timer <= CLKS_PER_BIT - 1;
        bit_index <= bit_index + 1'b1;
    end
end
endmodule
