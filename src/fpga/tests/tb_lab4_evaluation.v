`timescale 1ns/1ps
module tb_lab4_evaluation;
localparam CLKS_PER_BIT = 32;
reg clk = 0;
reg [7:0] symbol = 0;
reg send = 0;
wire rx, tx, ready;
wire [17:0] address;
wire [15:0] data;
wire ce_n, oe_n, we_n, lb_n, ub_n;
wire [27:0] hex_pins;
wire [27:0] display = ~hex_pins;
reg [15:0] memory [0:6];
assign #45 data = !ce_n && !oe_n && we_n ? memory[address] : 16'bz;
always #10 clk = !clk;
always @(posedge we_n) if (!ce_n) memory[address] = data;

lab4_evaluation #(.CLKS_PER_BIT(CLKS_PER_BIT), .STEP_CYCLES(500)) dut (
    .clk(clk), .rx(rx), .tx(tx), .hex0(hex_pins[6:0]), .hex1(hex_pins[13:7]),
    .hex2(hex_pins[20:14]), .hex3(hex_pins[27:21]),
    .sram_a(address), .sram_d(data), .ce_n(ce_n), .oe_n(oe_n), .we_n(we_n),
    .lb_n(lb_n), .ub_n(ub_n)
);
uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT), .EVEN_PARITY(1)) sender (
    .clk(clk), .reset(1'b0), .data(symbol), .valid(send), .ready(ready), .tx(rx), .busy()
);
wire [7:0] reply;
wire valid, parity_error, framing_error;
reg [55:0] replies = 0;
integer count = 0;
uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT), .EVEN_PARITY(1)) monitor (
    .clk(clk), .reset(1'b0), .rx(tx), .data(reply), .valid(valid),
    .parity_error(parity_error), .framing_error(framing_error)
);
always @(posedge clk) begin
    if (parity_error || framing_error) $fatal(1, "Invalid UART reply");
    if (valid) begin
        count <= count + 1;
        replies <= {replies[47:0], reply};
    end
end

task byte_in;
    input [7:0] value;
    begin
        @(negedge clk);
        symbol = value;
        send = 1;
        @(negedge clk);
        send = 0;
        wait (ready);
    end
endtask

initial begin
    byte_in("1"); byte_in("2"); byte_in("3"); byte_in("4");
    wait (count == 4);
    if (display !== 0 || {memory[0], memory[3]} !== 32'h00310034 || replies[31:0] !== "1234")
        $fatal(1, "UART bytes must echo and enter SRAM before display");
    // Alter the physical memory model to distinguish a read from a cached copy.
    memory[0] = 16'h0039;
    byte_in(8'h0d);
    wait (count == 11);
    if (display !== {7'h6f,7'h5b,7'h4f,7'h66} || replies !== 56'h1b5b324a1b5b48)
        $fatal(1, "Enter must display SRAM data and clear the terminal");

    byte_in("1"); byte_in("2"); byte_in("3"); byte_in("4"); byte_in("5"); byte_in("6");
    wait (count == 17);
    if (display !== {7'h6f,7'h5b,7'h4f,7'h66} || memory[0] !== 16'h0031)
        $fatal(1, "The next string must overwrite SRAM before changing the display");
    byte_in(8'h0d);
    wait (display == {7'h06,7'h5b,7'h4f,7'h66});
    wait (display == {7'h5b,7'h4f,7'h66,7'h6d});
    wait (display == {7'h4f,7'h66,7'h6d,7'h7d});
    wait (display == {7'h5b,7'h4f,7'h66,7'h6d});
    $display("PASS: UART echo, Enter, SRAM readback and overwrite, bouncing text");
    $finish;
end
initial #1000000 $fatal(1, "Lab 4 simulation timeout");
endmodule
