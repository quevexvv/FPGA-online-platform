`timescale 1ns/1ps
module lab3_evaluation #(
    parameter CLKS_PER_BIT = 434,
    parameter STEP_CYCLES = 12500000,
    parameter SETTLE_CYCLES = 250000,
    parameter IGNORE_ENTER = 0
) (
    input wire clk, rx,
    output wire tx,
    output wire [6:0] hex0, hex1, hex2, hex3
);
wire [27:0] display;
assign {hex3, hex2, hex1, hex0} = ~display;

lab3_text #(.CLKS_PER_BIT(CLKS_PER_BIT), .STEP_CYCLES(STEP_CYCLES), .IGNORE_ENTER(IGNORE_ENTER))
    example (.clk(clk), .rx(rx), .tx(tx), .display(display));

// The observer decodes the external RX line and samples actual output
// signals, independently of the DUT's UART flags and animation state.
wire [7:0] input_byte;
wire input_valid, bad_parity;
reg [2:0] bytes_seen = 0;
uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT), .EVEN_PARITY(1)) monitor (
    .clk(clk), .reset(1'b0), .rx(rx), .data(input_byte), .valid(input_valid),
    .framing_error(), .parity_error(bad_parity)
);
always @(posedge clk)
    if (input_valid && bytes_seen < 6) bytes_seen <= bytes_seen + 1'b1;

wire [2:0] before_count, after_count;
wire [139:0] before_frames, after_frames;
lab3_trace #(.SETTLE_CYCLES(SETTLE_CYCLES)) trace (
    .clk(clk), .start_text(bytes_seen == 6), .start_bad(bad_parity),
    .finish_text(input_valid && input_byte == 8'h0d),
    .display(~{hex3, hex2, hex1, hex0}),
    .before_count(before_count), .after_count(after_count),
    .before_frames(before_frames), .after_frames(after_frames)
);

wire request, ack;
wire [313:0] snapshot;
jtag_snapshot #(.WIDTH(314)) capture (
    .clk(clk), .request(request), .ack(ack), .snapshot(snapshot),
    .live({before_count, after_count, ~{hex3, hex2, hex1, hex0},
           before_frames, after_frames})
);
altsource_probe #(
    .instance_id("L3TR"), .sld_auto_instance_index("NO"), .sld_instance_index(0),
    .source_width(1), .probe_width(315), .source_initial_value("0"),
    .enable_metastability("YES")
) trace_probe (
    .source_clk(clk), .source_ena(1'b1), .source(request), .probe({ack, snapshot})
);
endmodule
