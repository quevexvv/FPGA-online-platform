module jtag_probe (
    input wire clk,
    output reg led = 1'b0
);

wire control;
wire request;
wire ack;
wire [29:0] snapshot;
reg [15:0] counter = 16'd0;

// Bit order is g..a. A set bit represents a lit segment.
function [6:0] segments;
    input [3:0] digit;
    begin
        case (digit)
            4'h0: segments = 7'h3f;
            4'h1: segments = 7'h06;
            4'h2: segments = 7'h5b;
            4'h3: segments = 7'h4f;
            4'h4: segments = 7'h66;
            4'h5: segments = 7'h6d;
            4'h6: segments = 7'h7d;
            4'h7: segments = 7'h07;
            4'h8: segments = 7'h7f;
            4'h9: segments = 7'h6f;
            4'ha: segments = 7'h77;
            4'hb: segments = 7'h7c;
            4'hc: segments = 7'h39;
            4'hd: segments = 7'h5e;
            4'he: segments = 7'h79;
            4'hf: segments = 7'h71;
            default: segments = 7'h00;
        endcase
    end
endfunction

always @(posedge clk) begin
    led <= control;
    counter <= counter + 1'b1;
end

jtag_snapshot capture (
    .clk(clk),
    .request(request),
    .live({counter, segments(counter[7:4]), segments(counter[3:0])}),
    .ack(ack),
    .snapshot(snapshot)
);

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

altsource_probe #(
    .instance_id("SNAP"),
    .sld_auto_instance_index("NO"),
    .sld_instance_index(1),
    .source_width(1),
    .probe_width(31),
    .source_initial_value("0"),
    .enable_metastability("YES")
) snapshot_probe (
    .source_clk(clk),
    .source_ena(1'b1),
    .source(request),
    .probe({ack, snapshot})
);

endmodule
