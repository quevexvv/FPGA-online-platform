`timescale 1ns/1ps
module tb_fpga_wrapper;
parameter integer COMBINATIONAL = 0;
localparam BIT_NS = 16 * 20;
reg clk = 0, rx = 1;
wire tx;
wire [17:0] led;
reg [63:0] expected [0:31];
reg [63:0] response = 0;
reg [7:0] decoded;
integer planned = 0, replies = 0, bytes = 0, b, i;
integer edges = 0, reset_edges = 0;
fpga_wrapper #(.CLKS_PER_BIT(16), .HALF_PERIOD(2)) dut (.clk(clk), .rx(rx), .tx(tx), .led(led));
always #10 clk = ~clk;
always @(posedge dut.dut_clk) begin
    if (dut.dut_reset) reset_edges = reset_edges + 1;
    else edges = edges + 1;
end
initial forever begin
    @(negedge tx); #(BIT_NS / 2);
    if (tx !== 0) $fatal(1, "Wrapper start bit");
    for (b = 0; b < 8; b = b + 1) begin #(BIT_NS); decoded[b] = tx; end
    #(BIT_NS);
    if (tx !== 1) $fatal(1, "Wrapper stop bit");
    response = {response[55:0], decoded};
    if (bytes == 7) begin
        if (replies >= planned || response !== expected[replies])
            $fatal(1, "Wrapper reply %0d: %h expected %h", replies, response, expected[replies]);
        replies = replies + 1; bytes = 0;
    end else bytes = bytes + 1;
end
task send_byte;
    input [7:0] value;
    integer bit_index;
    begin
        rx = 0; #(BIT_NS);
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            rx = value[bit_index]; #(BIT_NS);
        end
        rx = 1; #(BIT_NS);
    end
endtask
task exchange;
    input [63:0] text;
    input [63:0] reply;
    begin
        expected[planned] = reply; planned = planned + 1;
        for (i = 7; i >= 0; i = i - 1) if (text[i*8 +: 8] != 0) send_byte(text[i*8 +: 8]);
        wait (replies == planned);
        #(BIT_NS * 2);
    end
endtask
initial begin #10000000; $fatal(1, "Wrapper watchdog"); end
initial begin
    #(BIT_NS * 3 + 7);
    exchange("1R0000\n", "1K00000\n");
    exchange("1I0001\n", "1K00000\n");
    exchange("1S0000\n", "1K00000\n");
    exchange("1S0003\n", "1K00000\n");
    exchange("1Q0000\n", COMBINATIONAL ? "1D00001\n" : "1D00003\n");
    if (led !== (COMBINATIONAL ? 18'd1 : 18'd3) || edges != 3 || reset_edges != 2)
        $fatal(1, "Wrapper LED or physical edge mismatch");
    exchange("1I0002\n", "1K00000\n");
    exchange("1S0001\n", "1K00000\n");
    exchange("1Q0000\n", COMBINATIONAL ? "1D00002\n" : "1D00005\n");
    exchange("1I0400\n", "1E00004\n");
    exchange("1R00000\n", "1E00002\n");
    exchange("1Q0000\n", COMBINATIONAL ? "1D00002\n" : "1D00005\n");
    if (edges != 4 || reset_edges != 2) $fatal(1, "Error request changed DUT");
    exchange("1R0000\n", "1K00000\n");
    exchange("1I0001\n", "1K00000\n");
    exchange("1S0000\n", "1K00000\n");
    exchange("1Q0000\n", COMBINATIONAL ? "1D00001\n" : "1D00000\n");
    exchange("1S0001\n", "1K00000\n");
    exchange("1Q0000\n", "1D00001\n");
    exchange("1S0007\n", "1K00000\n");
    exchange("1Q0000\n", COMBINATIONAL ? "1D00001\n" : "1D00008\n");
    exchange("1Sffff\n", "1K00000\n");
    exchange("1S0002\n", "1K00000\n");
    exchange("1Q0000\n", COMBINATIONAL ? "1D00001\n" : "1D10009\n");
    #(BIT_NS * 1000);
    exchange("1Q0000\n", COMBINATIONAL ? "1D00001\n" : "1D10009\n");
    if (edges != 65549 || reset_edges != 4) $fatal(1, "Burst or idle edge mismatch");
    exchange("1R0000\n", "1K00000\n");
    exchange("1Q0000\n", COMBINATIONAL ? "1D00001\n" : "1D00000\n");
    exchange("1S0003\n", "1K00000\n");
    exchange("1Q0000\n", COMBINATIONAL ? "1D00001\n" : "1D00003\n");
    if (edges != 65552 || reset_edges != 6) $fatal(1, "Restart edge mismatch");
    $display("PASS: full UART wrapper, combinational=%0d", COMBINATIONAL); $finish;
end
endmodule
