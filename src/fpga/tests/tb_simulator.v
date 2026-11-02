`timescale 1ns/1ps
module tb_simulator;
reg clk = 0;
reg [3:0] counter = 0;
always #10 clk = ~clk;
always @(posedge clk) counter <= counter + 1'b1;
initial begin
    repeat (7) @(negedge clk);
`ifdef NEGATIVE_TEST
    if (counter !== 8) $finish_and_return(1);
`else
    if (counter !== 7) $finish_and_return(1);
`endif
    $display("PASS: Verilog-2001 counter");
    $finish;
end
endmodule
