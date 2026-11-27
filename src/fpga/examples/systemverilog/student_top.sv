`timescale 1ns/1ps
module student_top (
    input logic clk, reset,
    input logic [9:0] din,
    output logic [17:0] dout
);
always_ff @(posedge clk) begin
    if (reset) dout <= '0;
    else dout <= dout + {8'b0, din};
end
endmodule
