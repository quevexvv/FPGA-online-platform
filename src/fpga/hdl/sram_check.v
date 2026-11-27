`timescale 1ns/1ps
module sram_check #(parameter CHECK_HELPER = 0) (
    input wire clk,
    output wire [17:0] sram_a,
    inout wire [15:0] sram_d,
    output wire ce_n, oe_n, we_n, lb_n, ub_n
);
reg [3:0] step = 0;
reg pending = 0, helper_seen_busy = 0, helper_issued = 0, helper_bus_done = 0;
reg armed = 0;
reg [6:0] wait_cycles = 0;
reg [127:0] words = 0;
wire request, ack;
wire finished = step == 13 || wait_cycles == 64;
wire start = armed && !pending && !finished;
wire write_word = step < 4 || step == 8;
wire [1:0] slot = step == 8 ? 2'd1 : (step > 8 ? step[1:0] - 2'd1 : step[1:0]);
wire [17:0] address = slot == 0 ? 18'h00000 : slot == 1 ? 18'h00001 :
                      slot == 2 ? 18'h20000 : 18'h3ffff;
wire [15:0] value = step == 8 ? 16'h6996 : slot == 0 ? 16'h55aa :
                    slot == 1 ? 16'h1248 : slot == 2 ? 16'ha55a : 16'he817;
wire done;
wire [15:0] read_data;
wire helper_selected = CHECK_HELPER && step >= 4 && step <= 8;
wire helper_busy, mem_request, mem_write;
wire [17:0] mem_address;
wire [15:0] helper_data, mem_data;
wire allowed = mem_address == 0 || mem_address == 1 ||
               mem_address == 18'h20000 || mem_address == 18'h3ffff;
wire launch_helper = helper_selected && pending && !helper_issued && mem_request;
wire complete = helper_selected ?
    helper_seen_busy && helper_issued && helper_bus_done && !helper_busy : done;

generate if (CHECK_HELPER) begin : helper_path
    student_sram_helper student (
        .clk(clk), .request(start && helper_selected), .write_word(write_word),
        .address(address), .data_in(value), .busy(helper_busy), .data_out(helper_data),
        .mem_request(mem_request), .mem_write(mem_write), .mem_address(mem_address),
        .mem_data(mem_data), .mem_done(done && helper_selected), .mem_result(read_data)
    );
end else begin : direct_path
    assign {helper_busy, mem_request, mem_write, mem_address, helper_data, mem_data} = 0;
end endgenerate

c5g_sram_word bus_access (
    .clk(clk), .start(helper_selected ? !finished && launch_helper && allowed : start),
    .write_word(helper_selected ? mem_write : write_word),
    .address(helper_selected ? mem_address : address),
    .write_data(helper_selected ? mem_data : value),
    .done(done), .read_data(read_data), .sram_a(sram_a), .sram_d(sram_d),
    .ce_n(ce_n), .oe_n(oe_n), .we_n(we_n), .lb_n(lb_n), .ub_n(ub_n)
);

always @(posedge clk) begin
    // The first JTAG request arrives after configuration has released the pins.
    if (request) armed <= 1;
    if (start) begin
        pending <= 1;
        helper_seen_busy <= 0;
        helper_issued <= 0;
        helper_bus_done <= 0;
    end
    if (pending && !finished) begin
        wait_cycles <= wait_cycles + 1'b1;
        if (helper_busy) helper_seen_busy <= 1;
        if (launch_helper) helper_issued <= 1;
        if (done) helper_bus_done <= 1;
        if (helper_selected && helper_seen_busy && !helper_busy && !helper_bus_done && !done)
            wait_cycles <= 64;
    end
    if (pending && !finished && complete) begin
        if (!write_word)
            words <= {words[111:0], helper_selected ? helper_data : read_data};
        step <= step + 1'b1;
        pending <= 0;
        wait_cycles <= 0;
    end
end

wire [128:0] snapshot;
jtag_snapshot #(.WIDTH(129)) capture (
    .clk(clk), .request(request), .ack(ack), .live({finished, words}), .snapshot(snapshot)
);
altsource_probe #(
    .instance_id(CHECK_HELPER ? "SRHP" : "SRCK"),
    .sld_auto_instance_index("NO"), .sld_instance_index(0),
    .source_width(1), .probe_width(130), .source_initial_value("0"), .enable_metastability("YES")
) trace_probe (
    .source_clk(clk), .source_ena(1'b1), .source(request), .probe({ack, snapshot})
);
endmodule
