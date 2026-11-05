`timescale 1ns/1ps
module tb_uart_rx;
parameter integer CLKS_PER_BIT = 16;
localparam BIT_NS = CLKS_PER_BIT * 20;
reg clk = 0, reset = 1, rx = 1;
wire [7:0] data;
wire valid, framing_error;
integer received = 0, errors = 0, planned = 0, i;
reg [7:0] expected [0:511];
reg previous_valid = 0, previous_error = 0;
uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
    .clk(clk), .reset(reset), .rx(rx), .data(data),
    .valid(valid), .framing_error(framing_error)
);
always #10 clk = ~clk;
always @(negedge clk) begin
    if ((valid && previous_valid) || (framing_error && previous_error) ||
        (valid && framing_error)) $fatal(1, "Invalid RX strobes");
    previous_valid = valid;
    previous_error = framing_error;
    if (valid) begin
        if (received >= planned || data !== expected[received])
            $fatal(1, "RX byte %0d: got %h expected %h", received, data, expected[received]);
        received = received + 1;
    end
    if (framing_error) errors = errors + 1;
end

task send_byte;
    input [7:0] value;
    input good_stop;
    input integer bit_ns;
    integer b;
    begin
        if (good_stop) begin
            expected[planned] = value;
            planned = planned + 1;
        end
        rx = 0; #(bit_ns);
        for (b = 0; b < 8; b = b + 1) begin rx = value[b]; #(bit_ns); end
        rx = good_stop; #(bit_ns);
    end
endtask

initial begin
    #(BIT_NS * 4000);
    $fatal(1, "RX watchdog");
end
initial begin
    repeat (4) @(negedge clk);
    reset = 0;
    #(BIT_NS * 2 + 3);
    // False start must not publish a byte or a framing error.
    rx = 0; #20; rx = 1; #(BIT_NS * 2);
    if (received != 0 || errors != 0) $fatal(1, "False start accepted");
    // Back-to-back bytes exercise every bit pattern with one stop bit.
    for (i = 0; i < 256; i = i + 1) send_byte(i, 1, BIT_NS);
    #7;
    send_byte(8'h55, 1, BIT_NS);
    #11;
    send_byte(8'haa, 1, BIT_NS);
    // Sender clock differs by about 1% in both directions.
    send_byte(8'h81, 1, BIT_NS + BIT_NS / 100);
    send_byte(8'h7e, 1, BIT_NS - BIT_NS / 100);
    send_byte(8'hff, 0, BIT_NS);
    rx = 0; #(BIT_NS * 12);
    if (errors != 1) $fatal(1, "Break must report one framing error");
    rx = 1; #(BIT_NS * 2);
    send_byte(8'h42, 1, BIT_NS);
    // Reset during a partial frame must discard that byte.
    rx = 0; #(BIT_NS * 4);
    @(negedge clk); reset = 1; rx = 1;
    repeat (4) @(negedge clk);
    reset = 0; #(BIT_NS * 2 + 5);
    send_byte(8'h19, 1, BIT_NS);
    #(BIT_NS * 12);
    if (received != planned || errors != 1) $fatal(1, "RX count mismatch");
    $display("PASS: UART RX, %0d bytes, divider %0d", received, CLKS_PER_BIT);
    $finish;
end
endmodule
