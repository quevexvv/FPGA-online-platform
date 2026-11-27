`timescale 1ns/1ps
module lab4_evaluation #(parameter CLKS_PER_BIT = 434, STEP_CYCLES = 12500000) (
    input wire clk, rx,
    output wire tx,
    output wire [6:0] hex0, hex1, hex2, hex3,
    output wire [17:0] sram_a,
    inout wire [15:0] sram_d,
    output wire ce_n, oe_n, we_n, lb_n, ub_n
);
wire [27:0] display;
wire start, write_word, done;
wire [17:0] addr;
wire [15:0] data, read_data;
assign {hex3, hex2, hex1, hex0} = ~display;
lab4_text #(.CLKS_PER_BIT(CLKS_PER_BIT), .STEP_CYCLES(STEP_CYCLES)) example (
    .clk(clk), .rx(rx), .tx(tx), .display(display),
    .mem_request(start), .mem_write(write_word), .mem_address(addr), .mem_data(data),
    .mem_done(done), .mem_result(read_data)
);
c5g_sram_word bus_access (
    .clk(clk), .start(start), .write_word(write_word), .address(addr), .write_data(data),
    .done(done), .read_data(read_data), .sram_a(sram_a), .sram_d(sram_d),
    .ce_n(ce_n), .oe_n(oe_n), .we_n(we_n), .lb_n(lb_n), .ub_n(ub_n)
);
wire request, ack;
wire [27:0] snapshot;
jtag_snapshot #(.WIDTH(28)) capture (
    .clk(clk), .request(request), .ack(ack),
    .live(~{hex3, hex2, hex1, hex0}), .snapshot(snapshot)
);
altsource_probe #(
    .instance_id("L4FR"), .sld_auto_instance_index("NO"), .sld_instance_index(0),
    .source_width(1), .probe_width(29), .source_initial_value("0"), .enable_metastability("YES")
) trace_probe (
    .source_clk(clk), .source_ena(1'b1), .source(request), .probe({ack, snapshot})
);
endmodule
