`timescale 1ns/1ps
module jtag_snapshot #(
    parameter WIDTH = 30
) (
    input wire clk,
    input wire request,
    input wire [WIDTH-1:0] live,
    output reg ack = 1'b0,
    output reg [WIDTH-1:0] snapshot = {WIDTH{1'b0}}
);

// The request arrives synchronized to clk. The host holds it until ack.
reg pending = 1'b0;

always @(posedge clk) begin
    if (pending) begin
        // Publish acknowledgment one clock after latching the entire payload.
        ack <= ~ack;
        pending <= 1'b0;
    end else if (request != ack) begin
        snapshot <= live;
        pending <= 1'b1;
    end
end

endmodule
