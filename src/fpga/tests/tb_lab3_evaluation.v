`timescale 1ns/1ps
module tb_lab3_evaluation #(parameter IGNORE_ENTER = 0);
localparam CLKS_PER_BIT = 32, BIT_NS = CLKS_PER_BIT * 10;
reg clk = 0, rx = 1;
wire tx;
wire [6:0] hex0, hex1, hex2, hex3;
wire [314:0] trace = dut.trace_probe.probe;
wire [7:0] reply;
wire reply_valid, reply_parity_error, reply_stop_error;
reg [111:0] uart_data = 0;
integer uart_count = 0;

always #5 clk = ~clk;
lab3_evaluation #(
    .CLKS_PER_BIT(CLKS_PER_BIT), .STEP_CYCLES(1200), .SETTLE_CYCLES(24),
    .IGNORE_ENTER(IGNORE_ENTER)
) dut (
    .clk(clk), .rx(rx), .tx(tx), .hex0(hex0), .hex1(hex1), .hex2(hex2), .hex3(hex3)
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
    #60000;
    send("9", 1);
    #60000;
    send(8'h0d, 0);
    #30000;
    if (uart_count != 14 || uart_data !== 112'h313233343536251b5b324a1b5b48)
        $fatal(1, "Unexpected UART transcript");
    dut.trace_probe.source = 1;
    #40;
    if (trace[314:308] !== {1'b1, 3'd5, 3'd5}) $fatal(1, "Incomplete JTAG trace");
    if (trace[307:280] !== ~{hex3, hex2, hex1, hex0}) $fatal(1, "Wrong pin polarity");
    if (!$value$plusargs("trace=%s", filename)) $fatal(1, "Missing trace output");
    file = $fopen(filename, "w");
    if (!file) $fatal(1, "Cannot open trace output");
    $fdisplay(file, "{\"schema_version\":1,\"current\":%0d,\"before\":[%0d,%0d,%0d,%0d,%0d],\"after\":[%0d,%0d,%0d,%0d,%0d]}",
        trace[307:280], trace[279:252], trace[251:224], trace[223:196],
        trace[195:168], trace[167:140], trace[139:112], trace[111:84],
        trace[83:56], trace[55:28], trace[27:0]);
    $fclose(file);
    $finish;
end
endmodule

// Model only the ISSP ports. The test drives the synchronized source.
module altsource_probe #(
    parameter instance_id = "", sld_auto_instance_index = "",
    parameter sld_instance_index = 0, source_width = 1, probe_width = 1,
    parameter source_initial_value = "0", enable_metastability = ""
) (
    input wire source_clk, source_ena,
    input wire [probe_width-1:0] probe,
    output reg [source_width-1:0] source = 0
);
endmodule
