`timescale 1ns/1ps
module tb_clock_burst;
parameter HALF_PERIOD = 2;
reg clk = 0, start = 0, reset_command = 0;
reg [15:0] steps = 0;
wire dut_clk, dut_reset, busy, done;
integer edges = 0, resets = 0, i;
time last_rise = 0, last_fall = 0;
clock_burst #(.HALF_PERIOD(HALF_PERIOD)) generator (
    .clk(clk), .start(start), .reset_command(reset_command), .steps(steps),
    .dut_clk(dut_clk), .dut_reset(dut_reset), .busy(busy), .done(done)
);
always #10 clk = ~clk;
always @(posedge dut_clk) begin
    if ($time - last_fall < 20 * HALF_PERIOD) $finish_and_return(1);
    last_rise = $time;
    if (dut_reset) resets = resets + 1;
    else edges = edges + 1;
end
always @(negedge dut_clk) begin
    if (last_rise != 0 && $time - last_rise != 20 * HALF_PERIOD) $finish_and_return(1);
    last_fall = $time;
end
task command;
    input [15:0] n;
    input reset_op;
    integer before_edges, before_resets, pulses;
    time accepted;
    begin
        before_edges = edges;
        before_resets = resets;
        pulses = reset_op ? 2 : n;
        @(negedge clk); steps = n; reset_command = reset_op; start = 1;
        @(posedge clk); accepted = $time;
        @(negedge clk); start = 0;
        wait (done); #1;
        if ($time - accepted != (2 * pulses + 1) * HALF_PERIOD * 20 + 1)
            $finish_and_return(1);
        if (pulses != 0 && last_fall - accepted != 2 * pulses * HALF_PERIOD * 20)
            $finish_and_return(1);
        if (busy || dut_clk || dut_reset) $finish_and_return(1);
        if (edges - before_edges != (reset_op ? 0 : n)) $finish_and_return(1);
        if (resets - before_resets != (reset_op ? 2 : 0)) $finish_and_return(1);
        repeat (20) @(negedge clk);
        if (edges - before_edges != (reset_op ? 0 : n)) $finish_and_return(1);
        if (resets - before_resets != (reset_op ? 2 : 0)) $finish_and_return(1);
    end
endtask
initial begin
    #1;
    command(0, 0); command(1, 0); command(3, 0);
    command(65535, 1); // Reset ignores steps, emits two separate reset pulses.
    for (i = 0; i < 20; i = i + 1) command(i, 0);
    command(65535, 0); command(0, 0); command(1, 0);
    // Busy commands are ignored; they must not queue another burst.
    i = edges;
    @(negedge clk); steps = 3; reset_command = 0; start = 1;
    repeat (5) @(negedge clk);
    start = 0;
    wait (done); #1;
    if (edges != i + 3) $finish_and_return(1);
    i = edges;
    repeat (1000) @(negedge clk);
    if (edges != i || busy || dut_clk) $finish_and_return(1);
    $display("PASS: STEP 0/1/N/65535, reset, busy, full pulses, long stop");
    $finish;
end
initial begin
    #100000000;
    $display("FAIL: watchdog");
    $finish_and_return(1);
end
endmodule
