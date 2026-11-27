`timescale 1ns/1ps
module sram_check (
    input wire clk,
    output wire [17:0] sram_a,
    inout wire [15:0] sram_d,
    output wire ce_n, oe_n, we_n, lb_n, ub_n
);
reg [3:0] step = 0;
reg pending = 0;
reg armed = 0;
reg [127:0] words = 0;
wire request, ack;
wire finished = step == 13;
wire start = armed && !pending && !finished;
wire write_word = step < 4 || step == 8;
wire [1:0] slot = step == 8 ? 2'd1 : (step > 8 ? step[1:0] - 2'd1 : step[1:0]);
wire [17:0] address = slot == 0 ? 18'h00000 : slot == 1 ? 18'h00001 :
                      slot == 2 ? 18'h20000 : 18'h3ffff;
wire [15:0] value = step == 8 ? 16'h6996 : slot == 0 ? 16'h55aa :
                    slot == 1 ? 16'h1248 : slot == 2 ? 16'ha55a : 16'he817;
wire done;
wire [15:0] read_data;
c5g_sram_word bus_access (
    .clk(clk), .start(start), .write_word(write_word), .address(address), .write_data(value),
    .done(done), .read_data(read_data), .sram_a(sram_a), .sram_d(sram_d),
    .ce_n(ce_n), .oe_n(oe_n), .we_n(we_n), .lb_n(lb_n), .ub_n(ub_n)
);

always @(posedge clk) begin
    // The first JTAG request arrives after configuration has released the pins.
    if (request) armed <= 1;
    if (start) pending <= 1;
    if (done) begin
        if (!write_word) words <= {words[111:0], read_data};
        step <= step + 1'b1;
        pending <= 0;
    end
end

wire [128:0] snapshot;
jtag_snapshot #(.WIDTH(129)) capture (
    .clk(clk), .request(request), .ack(ack), .live({finished, words}), .snapshot(snapshot)
);
altsource_probe #(
    .instance_id("SRCK"), .sld_auto_instance_index("NO"), .sld_instance_index(0),
    .source_width(1), .probe_width(130), .source_initial_value("0"), .enable_metastability("YES")
) trace_probe (
    .source_clk(clk), .source_ena(1'b1), .source(request), .probe({ack, snapshot})
);
endmodule
