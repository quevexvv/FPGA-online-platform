`timescale 1ns/1ps
module tb_lab3_uart_probe;
localparam CLKS_PER_BIT = 32, BIT_NS = 10 * CLKS_PER_BIT;
reg clk = 0, rx = 1;
wire tx;
reg [7:0] replies [0:15];
integer count = 0;

always #5 clk = ~clk;
lab3_uart_probe #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (.clk(clk), .rx(rx), .tx(tx));

task send_frame;
    input [7:0] data;
    input wrong_parity;
    input stop;
    integer bit_number;
    begin
        rx = 0;
        #BIT_NS;
        for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
            rx = data[bit_number];
            #BIT_NS;
        end
        rx = (^data) ^ wrong_parity;
        #BIT_NS;
        rx = stop;
        #BIT_NS;
        rx = 1;
    end
endtask

always @(negedge tx) begin : read_reply
    reg [7:0] data;
    reg parity;
    integer bit_number;
    #(BIT_NS + BIT_NS / 2);
    for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
        data[bit_number] = tx;
        #BIT_NS;
    end
    parity = tx;
    #BIT_NS;
    if (parity !== (^data) || tx !== 1'b1) $fatal(1, "Invalid 8E1 reply");
    if (count > 15) $fatal(1, "Too many replies");
    replies[count] = data;
    count = count + 1;
end

initial begin
    #BIT_NS;
    send_frame("A", 0, 1);
    send_frame("B", 0, 1);
    send_frame("C", 0, 1);
    send_frame("D", 0, 1);
    send_frame("E", 0, 1);
    send_frame(8'h0d, 0, 1);
    send_frame("Z", 0, 1);
    send_frame("A", 1, 1);  // An even number of set bits.
    send_frame("C", 1, 1);  // An odd number of set bits.
    send_frame(8'h0d, 1, 1);
    send_frame("X", 0, 0);  // A bad stop bit is not a parity error.
    #(2 * BIT_NS);
    send_frame(8'h0d, 0, 1);
    send_frame("Z", 0, 1);
    send_frame(8'h0d, 0, 1);
    #(12 * BIT_NS);
    if (count != 13 ||
        {replies[0], replies[1], replies[2], replies[3], replies[4], replies[5],
         replies[6], replies[7], replies[8], replies[9], replies[10], replies[11], replies[12]}
         !== "ABCD!4Z%%%1Z1")
        $fatal(1, "Unexpected parity, line limit or Enter behavior");
    $display("PASS: 8E1, parity rejection, bad stop bit, line limit and Enter");
    $finish;
end
endmodule
