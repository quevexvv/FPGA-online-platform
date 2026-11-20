`timescale 1ns/1ps
module tb_lab3_evaluation #(parameter IGNORE_ENTER = 0);
localparam CLKS_PER_BIT = 32, BIT_NS = CLKS_PER_BIT * 10;
reg clk = 0, rx = 1;
reg start_text = 0, start_bad = 0, finish_text = 0;
wire tx;
wire [27:0] display;
wire [2:0] before_count, after_count;
wire [139:0] before_frames, after_frames;
wire [7:0] reply;
wire reply_valid, reply_parity_error, reply_stop_error;
reg [111:0] uart_data = 0;
integer uart_count = 0;

always #5 clk = ~clk;
lab3_text #(.CLKS_PER_BIT(CLKS_PER_BIT), .STEP_CYCLES(1200), .IGNORE_ENTER(IGNORE_ENTER))
    dut (.clk(clk), .rx(rx), .tx(tx), .display(display));
lab3_trace #(.SETTLE_CYCLES(24)) trace (
    .clk(clk), .start_text(start_text), .start_bad(start_bad), .finish_text(finish_text),
    .display(display), .before_count(before_count), .after_count(after_count),
    .before_frames(before_frames), .after_frames(after_frames)
);
uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT), .EVEN_PARITY(1)) read_reply (
    .clk(clk), .reset(1'b0), .rx(tx), .data(reply), .valid(reply_valid),
    .parity_error(reply_parity_error), .framing_error(reply_stop_error)
);
always @(posedge clk) begin
    if (reply_parity_error || reply_stop_error) $fatal(1, "Invalid UART reply framing");
    if (reply_valid) begin
        uart_count <= uart_count + 1;
        uart_data <= {uart_data[103:0], reply};
    end
end

task send;
    input [7:0] data;
    input wrong;
    integer i;
    begin
        rx = 0;
        #BIT_NS;
        for (i = 0; i < 8; i = i + 1) begin
            rx = data[i];
            #BIT_NS;
        end
        rx = (^data) ^ wrong;
        #BIT_NS;
        rx = 1;
        #BIT_NS;
    end
endtask

integer file;
reg [255:0] filename;
initial begin
    @(negedge clk);
    send("1", 0); send("2", 0); send("3", 0);
    send("4", 0); send("5", 0); send("6", 0);
    start_text = 1;
    #10 start_text = 0;
    #60000;
    send("9", 1);
    start_bad = 1;
    #10 start_bad = 0;
    #60000;
    finish_text = 1;
    send(8'h0d, 0);
    #30000;
    if (uart_count != 14 || uart_data !== 112'h313233343536251b5b324a1b5b48)
        $fatal(1, "Unexpected UART transcript");
    if (before_count != 5 || after_count != 5) $fatal(1, "Incomplete trace");
    if (!$value$plusargs("trace=%s", filename)) $fatal(1, "Missing trace output");
    file = $fopen(filename, "w");
    if (!file) $fatal(1, "Cannot open trace output");
    $fdisplay(file, "{\"schema_version\":1,\"current\":%0d,\"before\":[%0d,%0d,%0d,%0d,%0d],\"after\":[%0d,%0d,%0d,%0d,%0d]}",
        display,
        before_frames[139:112], before_frames[111:84], before_frames[83:56],
        before_frames[55:28], before_frames[27:0],
        after_frames[139:112], after_frames[111:84], after_frames[83:56],
        after_frames[55:28], after_frames[27:0]);
    $fclose(file);
    $finish;
end
endmodule
