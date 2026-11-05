`timescale 1ns/1ps
module tb_dut_control;
reg clk = 0, reset = 1, request = 0, combinational = 0;
reg [7:0] command = 0;
reg [15:0] argument = 0;
wire [9:0] din;
wire dut_clk, dut_reset, done;
wire [17:0] snapshot;
reg [17:0] counter = 0;
wire [17:0] dout = combinational ? {8'd0, din} : counter;
integer edges = 0, reset_edges = 0;
reg [9:0] held_din;
dut_control #(.HALF_PERIOD(2)) dut (
    .clk(clk), .reset(reset), .request(request), .command(command), .argument(argument),
    .dout(dout), .din(din), .dut_clk(dut_clk), .dut_reset(dut_reset),
    .done(done), .snapshot(snapshot));
always #10 clk = ~clk;
always @(posedge dut_clk) begin
    if (dut_reset) begin counter <= 0; reset_edges = reset_edges + 1; end
    else begin counter <= counter + 1'b1; edges = edges + 1; end
    if (din !== held_din) $fatal(1, "Inputs changed during burst");
end
task issue;
    input [7:0] op;
    input [15:0] value;
    begin
        @(negedge clk); command = op; argument = value; request = 1;
        @(negedge clk); request = 0;
    end
endtask
task check;
    input [17:0] expected;
    integer before;
    begin
        wait (done); @(negedge clk);
        if (snapshot !== expected || dut_clk || dut_reset) $fatal(1, "Unstable snapshot");
        before = edges;
        repeat (20) @(negedge clk);
        if (snapshot !== expected || edges != before) $fatal(1, "Late clock edge");
    end
endtask
initial begin #1000000; $fatal(1, "Control watchdog"); end
initial begin
    held_din = 0;
    repeat (4) @(negedge clk); reset = 0;
    issue("R", 0); check(0);
    if (reset_edges != 2 || edges != 0) $fatal(1, "Reset counted as STEP");
    issue("I", 10'h155); check(0); held_din = 10'h155;
    issue("S", 0); check(0);
    issue("S", 1); check(1);
    issue("S", 7);
    // A spurious request cannot change inputs while a burst is running.
    issue("I", 10'h3ff); check(8);
    if (din !== 10'h155 || edges != 8) $fatal(1, "Busy control changed inputs");
    issue("Q", 0); check(8);
    issue("R", 0); check(0);
    if (edges != 8 || reset_edges != 4 || din !== held_din) $fatal(1, "Reset semantics");
    combinational = 1;
    issue("I", 10'h2aa); check(18'h002aa); held_din = 10'h2aa;
    issue("S", 0); check(18'h002aa);
    issue("Q", 0); check(18'h002aa);
    issue("S", 100);
    repeat (5) @(negedge clk); reset = 1;
    @(negedge clk);
    if (dut_clk || dut_reset || done || din != 0) $fatal(1, "Service reset did not stop clock");
    held_din = 0; reset = 0;
    issue("R", 0); check(0);
    $display("PASS: DUT inputs, reset, STEP, snapshot and service reset"); $finish;
end
endmodule
