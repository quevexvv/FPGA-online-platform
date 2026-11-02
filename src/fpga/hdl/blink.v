module blink (
    input wire clk,
    output reg led = 1'b0
);

// 50 MHz * 0.5 s = 25,000,000 cycles per LED toggle.
// Count 0..24,999,999; full blink period is 1 second.
// 25 bits hold up to 33,554,431.
reg [24:0] count = 25'd0;

always @(posedge clk) begin
    if (count == 25'd24999999) begin
        led <= ~led;
        count <= 25'd0;
    end
    else begin
        count <= count + 25'd1;
    end
end

endmodule

