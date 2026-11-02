`timescale 1ns/1ps
module tb_clock_board;
reg clk = 0;
wire [17:0] led;
integer completions = 0;
reg [9:0] expected;
reg [9:0] previous_display = 0;
clock_board #(.PAUSE(20), .HALF_PERIOD(2)) dut (.clk(clk), .led(led));
always #10 clk = ~clk;
always @(negedge clk) begin
    if (led[11]) $finish_and_return(1);
    if (dut.busy && led[9:0] !== previous_display) $finish_and_return(1);
    previous_display = led[9:0];
    if (dut.state == 2 && dut.delay_count == 0) begin
        if (dut.phase < 2) expected = 0;
        else if (dut.phase == 12) expected = 512;
        else expected = 10'b1 << (dut.phase - 2);
        if (led[9:0] !== expected || led[10] !== 1) $finish_and_return(1);
        completions = completions + 1;
        if (completions == 26) begin
            $display("PASS: board scenario, independent counter, two cycles");
            $finish;
        end
    end
end
initial begin #500000; $finish_and_return(1); end
endmodule
