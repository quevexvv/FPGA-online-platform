module jtag_probe (
    input wire clk,
    output reg led = 1'b0
);

wire control;

always @(posedge clk)
    led <= control;

altsource_probe #(
    .instance_id("JCHK"),
    .sld_auto_instance_index("NO"),
    .sld_instance_index(0),
    .source_width(1),
    .probe_width(2),
    .source_initial_value("0"),
    .enable_metastability("YES")
) control_probe (
    .source_clk(clk),
    .source_ena(1'b1),
    .source(control),
    .probe({~led, led})
);

endmodule
