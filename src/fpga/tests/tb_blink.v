`timescale 1ns/1ps

module tb_blink;

reg clk = 1'b0;
wire led;

blink dut (
    .clk(clk),
    .led(led)
);

always #10 clk = ~clk;

initial begin
#1;
if (led !== 1'b0) begin
    $display("FAIL: unexpected LED value");
    $finish_and_return(1);
end

repeat (24999999) @(negedge clk);
if (led !== 1'b0) begin
    $display("FAIL: unexpected LED value");
    $finish_and_return(1);
end

repeat (1) @(negedge clk);
if (led == 1'b1) begin
    repeat (24999999) @(negedge clk);
    if (led !== 1'b1) begin
        $display("FAIL: unexpected LED value");
        $finish_and_return(1);
    end

    repeat (1) @(negedge clk);

    if (led !== 1'b0) begin
        $display("FAIL: unexpected LED value");
        $finish_and_return(1);
    end

    $display("Succes!");
    $finish_and_return(0);
end

else begin
    $display("FAIL: unexpected LED value");
    $finish_and_return(1);
end

end

endmodule
