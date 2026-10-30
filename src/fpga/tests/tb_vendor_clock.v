`timescale 1ns/1ps
module tb_vendor_clock;
reg clk = 0;
wire dut_clk;
always #10 clk = ~clk;
cyclonev_clkena #(
    .clock_type("global clock"),
    .ena_register_mode("falling edge"),
    .ena_register_power_up("low")
) gate (.inclk(clk), .ena(1'b0), .enaout(), .outclk(dut_clk));
initial begin
    #100;
    if (dut_clk !== 0) $finish_and_return(1);
    $display("PASS: vendor model elaborated, disabled clock is low");
    $finish;
end
endmodule
