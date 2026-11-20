`timescale 1ns/1ps
module tb_uart_tx;
parameter integer CLKS_PER_BIT = 16;
localparam BIT_NS = CLKS_PER_BIT * 20;
reg clk = 0, reset = 1, valid = 0, monitor_enable = 0;
reg [7:0] data = 0;
wire ready, tx, busy;
integer planned = 0, received = 0, accepted = 0, busy_cycles = 0, i, b;
reg [7:0] expected [0:511];
reg [7:0] decoded;
reg [63:0] reply = "1D3ffff\n";
uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
    .clk(clk), .reset(reset), .data(data), .valid(valid),
    .ready(ready), .tx(tx), .busy(busy)
);
always #10 clk = ~clk;
always @(posedge clk) if (monitor_enable && ready && valid) accepted = accepted + 1;
always @(negedge clk) if (monitor_enable) begin
    if (ready !== (!busy && !reset)) $fatal(1, "TX ready mismatch");
    if (busy) busy_cycles = busy_cycles + 1;
    else if (busy_cycles != 0) begin
        if (busy_cycles != 10 * CLKS_PER_BIT) $fatal(1, "TX frame length mismatch");
        busy_cycles = 0;
    end
    if (!busy && tx !== 1) $fatal(1, "TX idle must be high");
end
// Independent line decoder; it does not use the RX implementation.
initial forever begin
    @(negedge tx);
    if (monitor_enable) begin
        #(BIT_NS / 2);
        if (tx !== 0) $fatal(1, "Missing TX start bit");
        for (b = 0; b < 8; b = b + 1) begin
            #(BIT_NS); decoded[b] = tx;
        end
        #(BIT_NS);
        if (tx !== 1 || ready !== 0) $fatal(1, "Incomplete TX stop bit");
        if (received >= planned || decoded !== expected[received])
            $fatal(1, "TX byte %0d mismatch: %h", received, decoded);
        received = received + 1;
    end
end

task send_byte;
    input [7:0] value;
    begin
        @(negedge clk);
        data = value;
        valid = 1;
        expected[planned] = value;
        planned = planned + 1;
        // Keep data/valid stable while the transmitter is busy.
        @(posedge clk);
        while (!ready) @(posedge clk);
        @(negedge clk);
        valid = 0;
        data = ~value;
    end
endtask

initial begin
    #(BIT_NS * 4000);
    $fatal(1, "TX watchdog");
end
initial begin
    repeat (4) @(negedge clk);
    if (ready !== 0 || tx !== 1 || busy !== 0) $fatal(1, "TX reset mismatch");
    reset = 0;
    // Abort a frame with reset, then verify the next frame starts cleanly.
    @(negedge clk); valid = 1; data = 8'h00;
    @(negedge clk); valid = 0;
    #(BIT_NS * 3);
    @(negedge clk); reset = 1;
    @(negedge clk);
    if (tx !== 1 || busy !== 0 || ready !== 0) $fatal(1, "TX abort failed");
    reset = 0;
    @(negedge clk); monitor_enable = 1;
    send_byte(8'h81);
    wait (ready); #(BIT_NS * 3);
    for (i = 0; i < 256; i = i + 1) send_byte(i);
    for (i = 7; i >= 0; i = i - 1) send_byte(reply[i*8 +: 8]);
    wait (ready);
    #(BIT_NS * 12);
    if (received != planned || accepted != planned || busy_cycles != 0)
        $fatal(1, "TX lost or duplicated a byte");
    $display("PASS: UART TX, %0d bytes, divider %0d", received, CLKS_PER_BIT);
    $finish;
end
endmodule
