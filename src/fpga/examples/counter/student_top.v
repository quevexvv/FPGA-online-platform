`timescale 1ns/1ps
module student_top (
    input wire clk, reset,
    input wire [9:0] din,
    output reg [17:0] dout = 0
);
always @(posedge clk) begin
    if (reset) dout <= 0;
    else dout <= dout + {8'd0, din};
end
endmodule
