`timescale 1ns/1ps
// Trusted example for the digit-only variant A pilot.
module lab3_text #(
    parameter CLKS_PER_BIT = 434,
    parameter STEP_CYCLES = 12500000,
    parameter IGNORE_ENTER = 0
) (
    input wire clk, rx,
    output wire tx,
    output wire [27:0] display
);
wire [7:0] byte_in;
wire valid, parity_error, ready;
reg [55:0] reply = 0;
reg [2:0] remaining = 0;
reg [6:0] glyphs [0:6];
reg [2:0] length = 0;
reg [1:0] offset = 0;
reg reverse = 0;
reg [31:0] timer = 0;

function [6:0] glyph;
    input [7:0] digit;
    begin
        case (digit)
            "0": glyph = 7'h3f;
            "1": glyph = 7'h06;
            "2": glyph = 7'h5b;
            "3": glyph = 7'h4f;
            "4": glyph = 7'h66;
            "5": glyph = 7'h6d;
            "6": glyph = 7'h7d;
            "7": glyph = 7'h07;
            "8": glyph = 7'h7f;
            "9": glyph = 7'h6f;
            default: glyph = 0;
        endcase
    end
endfunction

genvar position;
generate for (position = 0; position < 4; position = position + 1) begin : digit
    wire [2:0] index = {1'b0, offset} + position[2:0];
    assign display[27-position*7 -: 7] = index < length ? glyphs[index] : 7'd0;
end endgenerate

uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT), .EVEN_PARITY(1)) receiver (
    .clk(clk), .reset(1'b0), .rx(rx), .data(byte_in), .valid(valid),
    .framing_error(), .parity_error(parity_error)
);
uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT), .EVEN_PARITY(1)) transmitter (
    .clk(clk), .reset(1'b0), .data(reply[7:0]), .valid(remaining != 0),
    .ready(ready), .tx(tx), .busy()
);

always @(posedge clk) begin
    if (length > 4) begin
        if (timer == STEP_CYCLES - 1) begin
            timer <= 0;
            if (reverse) begin
                offset <= offset - 1'b1;
                if (offset == 1) reverse <= 0;
            end else begin
                offset <= offset + 1'b1;
                if (offset + 1 == length - 4) reverse <= 1;
            end
        end else timer <= timer + 1'b1;
    end

    if (ready && remaining != 0) begin
        reply <= reply >> 8;
        remaining <= remaining - 1'b1;
    end
    if (remaining == 0 || (remaining == 1 && ready)) begin
        if (parity_error) begin
            reply <= 56'h25;
            remaining <= 1;
        end else if (valid && byte_in == 8'h0d) begin
            // ESC[2J ESC[H: erase the terminal and return the cursor home.
            reply <= 56'h485b1b4a325b1b;
            remaining <= 7;
            if (!IGNORE_ENTER) length <= 0;
            timer <= 0;
            offset <= 0;
            reverse <= 0;
        end else if (valid && length < 7 && byte_in >= "0" && byte_in <= "9") begin
            glyphs[length] <= glyph(byte_in);
            length <= length + 1'b1;
            reply <= {48'd0, byte_in};
            remaining <= 1;
            timer <= 0;
            offset <= 0;
            reverse <= 0;
        end
    end
end
endmodule
