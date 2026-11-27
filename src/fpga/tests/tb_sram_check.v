`timescale 1ns/1ps
module tb_sram_check #(parameter CHECK_HELPER = 0);
reg clk = 0;
always #10 clk = !clk;

wire [17:0] address;
wire [15:0] data;
wire ce_n, oe_n, we_n, lb_n, ub_n;
reg [15:0] memory [0:262143];
wire reading = !ce_n && !oe_n && we_n;
assign #45 data = reading ? memory[address] : 16'bz;

sram_check #(.CHECK_HELPER(CHECK_HELPER)) dut (
    .clk(clk), .sram_a(address), .sram_d(data),
    .ce_n(ce_n), .oe_n(oe_n), .we_n(we_n), .lb_n(lb_n), .ub_n(ub_n)
);

always @(posedge we_n)
    if (!ce_n) begin
        if (!oe_n || lb_n || ub_n || (^data === 1'bx))
            $fatal(1, "Invalid SRAM write or data bus contention");
        memory[address] = data;
    end

initial begin
    repeat (5) @(negedge clk);
    if (!ce_n || !oe_n || !we_n || data !== 16'bz)
        $fatal(1, "SRAM drove signals before the JTAG request");
    wait (dut.finished);
`ifdef LAB4_BAD_ADDRESS
    if (dut.words !== 128'h55aa_1248_55aa_e817_55aa_6996_a55a_e817)
        $fatal(1, "Expected address alias to corrupt the helper read: %h", dut.words);
`elsif LAB4_BAD_DATA
    if (dut.words !== 128'h55aa_1248_a55a_e817_55aa_6997_a55a_e817)
        $fatal(1, "Expected the trusted read to detect corrupt write data: %h", dut.words);
`else
    if (dut.words !== 128'h55aa_1248_a55a_e817_55aa_6996_a55a_e817)
        $fatal(1, "Unexpected SRAM readback: %h", dut.words);
`endif
    if (data !== 16'bz)
        $fatal(1, "SRAM data bus was not released");
    $display("PASS: SRAM boundaries, retention, overwrite and released data bus");
    $finish;
end
initial #10000 $fatal(1, "SRAM check timeout");
endmodule

module altsource_probe #(
    parameter instance_id = "", sld_auto_instance_index = "", sld_instance_index = 0,
    source_width = 1, probe_width = 130, source_initial_value = "", enable_metastability = ""
) (
    input wire source_clk, source_ena,
    output reg [source_width-1:0] source = 0,
    input wire [probe_width-1:0] probe
);
initial #200 source = 1;
endmodule
