`timescale 1ns/1ps
module student_top (
    input wire clk, reset,
    input wire [9:0] din,
    output wire [17:0] dout
);
assign dout = {8'd0, din};
endmodule
