`timescale 1ns/1ps
module tb_uart_commands;
reg clk = 0, reset = 1, rx_valid = 0, framing_error = 0, done = 0, tx_ready = 1;
reg [7:0] rx_data = 0;
wire [7:0] tx_data, command;
wire tx_valid, request;
wire [15:0] argument;
integer requests = 0, replies = 0, bytes = 0;
reg [63:0] received = 0, last_reply = 0;
uart_commands #(.GAP_TICKS(64)) dut (
    .clk(clk), .reset(reset), .rx_data(rx_data), .rx_valid(rx_valid),
    .framing_error(framing_error), .tx_data(tx_data), .tx_valid(tx_valid),
    .tx_ready(tx_ready), .tx_busy(1'b0), .request(request),
    .command(command), .argument(argument), .done(done), .snapshot(18'h123ab));
always #10 clk = ~clk;
always @(posedge clk) begin
    if (request) requests = requests + 1;
    if (tx_valid && tx_ready) begin
        received = {received[55:0], tx_data};
        if (bytes == 7) begin last_reply = received; replies = replies + 1; bytes = 0; end
        else bytes = bytes + 1;
    end
end
task byte_in;
    input [7:0] b;
    begin
        @(negedge clk); rx_valid = 1; rx_data = b;
        @(negedge clk); rx_valid = 0;
    end
endtask
task line;
    input [127:0] text;
    integer i;
    begin for (i = 15; i >= 0; i = i - 1) if (text[i*8 +: 8] != 0) byte_in(text[i*8 +: 8]); end
endtask
task expect_reply;
    input [63:0] expected;
    integer before;
    begin
        before = replies;
        wait (replies > before);
        if (last_reply !== expected) $fatal(1, "Reply %h expected %h", last_reply, expected);
        repeat (3) @(negedge clk);
    end
endtask
task complete;
    begin @(negedge clk); done = 1; @(negedge clk); done = 0; end
endtask
initial begin #1000000; $fatal(1, "Command watchdog"); end
initial begin
    repeat (3) @(negedge clk); reset = 0;
    line("1R0000\n");
    if (!dut.active || command != "R" || argument != 0) $fatal(1, "Reset request missing");
    line("1I0001\n"); expect_reply("1E00005\n");
    if (requests != 1 || command != "R") $fatal(1, "Busy request overwritten");
    complete; expect_reply("1K00000\n");
    line("1I03ff\n");
    if (argument != 1023 || command != "I") $fatal(1, "Input request mismatch");
    complete; expect_reply("1K00000\n");
    line("1Sffff\n");
    if (argument != 65535 || command != "S") $fatal(1, "Step request mismatch");
    complete; expect_reply("1K00000\n");
    line("1Q0000\n"); complete; expect_reply("1D123ab\n");
    line("2R0000\n"); expect_reply("1E00001\n");
    line("1X0000\n"); expect_reply("1E00003\n");
    line("1I0400\n"); expect_reply("1E00004\n");
    line("1R0001\n"); expect_reply("1E00004\n");
    line("1Q0001\n"); expect_reply("1E00004\n");
    line("1I00Af\n"); expect_reply("1E00002\n");
    line("1R00000\n"); expect_reply("1E00002\n");
    line("1R\n"); expect_reply("1E00002\n");
    line("1R0000\r\n"); expect_reply("1E00002\n");
    @(negedge clk); framing_error = 1;
    @(negedge clk); framing_error = 0;
    line("garbage\n"); expect_reply("1E00006\n");
    line("1R"); repeat (70) @(negedge clk);
    if (requests != 4 || dut.length != 0) $fatal(1, "Incomplete frame executed");
    // Hold the sender busy: queued error must not replace the completed result.
    tx_ready = 0; line("1S0000\n"); complete;
    line("1R0000\n");
    tx_ready = 1; expect_reply("1K00000\n"); expect_reply("1E00005\n");
    if (requests != 5) $fatal(1, "Unexpected execution");
    $display("PASS: UART commands, errors, timeout, busy and stalled replies"); $finish;
end
endmodule
