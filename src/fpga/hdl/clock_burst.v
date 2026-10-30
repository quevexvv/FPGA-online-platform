`timescale 1ns/1ps
// Experimental registered slow clock, independent of ALTCLKCTRL.
module clock_burst #(parameter HALF_PERIOD = 25, RESET_PULSES = 2) (
    input wire clk,
    input wire start,
    input wire reset_command,
    input wire [15:0] steps,
    output reg dut_clk = 0,
    output reg dut_reset = 0,
    output reg busy = 0,
    output reg done = 0
);
reg [15:0] remaining = 0;
reg [31:0] divider = 0;
reg draining = 0;
always @(posedge clk) begin
    done <= 0;
    if (!busy) begin
        if (start) begin
            busy <= 1;
            dut_reset <= reset_command;
            remaining <= reset_command ? RESET_PULSES : steps;
            divider <= HALF_PERIOD - 1;
            draining <= !reset_command && steps == 0;
        end
    end else if (divider != 0) divider <= divider - 1'b1;
    else if (draining) begin
        busy <= 0;
        done <= 1;
        dut_reset <= 0;
    end else begin
        divider <= HALF_PERIOD - 1;
        dut_clk <= ~dut_clk;
        if (dut_clk) begin
            remaining <= remaining - 1'b1;
            if (remaining == 1) draining <= 1;
        end
    end
end
endmodule
