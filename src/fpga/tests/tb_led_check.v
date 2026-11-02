`timescale 1ns/1ps
module tb_led_check;
reg clk = 0;
wire [17:0] led;
integer cycle, phase;
reg [17:0] expected;
led_check #(.PERIOD(2)) dut (.clk(clk), .led(led));
always #10 clk = ~clk;
initial begin
    #1;
    for (cycle = 0; cycle < 80; cycle = cycle + 1) begin
        phase = (cycle / 2) % 20;
        expected = 0;
        if (phase == 1) expected = 18'h3ffff;
        else if (phase >= 2) expected = 18'b1 << (phase - 2);
        if (led !== expected) $finish_and_return(1);
        @(negedge clk);
    end
    $display("PASS: LED off/all/walking-one, two loops");
    $finish;
end
endmodule
