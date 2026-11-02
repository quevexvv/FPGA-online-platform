`timescale 1ns/1ps
module led_check #(parameter PERIOD = 50000000) (
    input wire clk,
    output reg [17:0] led
);
reg [25:0] ticks = 0;
reg [4:0] phase = 0;
always @* begin
    led = 18'b0;
    if (phase == 1) led = 18'h3ffff;
    else if (phase >= 2) led = 18'b1 << (phase - 2);
end
always @(posedge clk) begin
    if (ticks == PERIOD - 1) begin
        ticks <= 0;
        if (phase == 19) phase <= 0;
        else phase <= phase + 1'b1;
    end else ticks <= ticks + 1'b1;
end
endmodule
