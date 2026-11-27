`timescale 1ns/1ps
module lab4_text #(
    parameter CLKS_PER_BIT = 434, STEP_CYCLES = 12500000
) (
    input wire clk, rx,
    output wire tx,
    output wire [27:0] display,
    output wire mem_request, mem_write,
    output wire [17:0] mem_address,
    output wire [15:0] mem_data,
    input wire mem_done,
    input wire [15:0] mem_result
);
localparam INPUT = 0, WRITE_WORD = 1, READ_WORD = 2;
reg [1:0] state = INPUT;
reg helper_request = 0, saw_busy = 0;
reg [2:0] index = 0, stored = 0, target = 0, visible = 0;
reg [7:0] symbol = 0;
reg [6:0] glyphs [0:6];
reg [2:0] offset = 0;
reg reverse = 0;
reg [31:0] timer = 0;
wire helper_busy;
wire [15:0] read_data;
wire [7:0] received;
wire valid, parity_error, tx_ready;
reg [55:0] reply = 0;
reg [2:0] remaining = 0;
wire can_reply = remaining == 0 || (remaining == 1 && tx_ready);

uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT), .EVEN_PARITY(1)) receiver (
    .clk(clk), .reset(1'b0), .rx(rx), .data(received), .valid(valid),
    .framing_error(), .parity_error(parity_error)
);
uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT), .EVEN_PARITY(1)) transmitter (
    .clk(clk), .reset(1'b0), .data(reply[7:0]), .valid(remaining != 0),
    .ready(tx_ready), .tx(tx), .busy()
);
student_sram_helper helper (
    .clk(clk), .request(helper_request), .write_word(state == WRITE_WORD),
    .address({15'd0, index}), .data_in({8'd0, symbol}), .busy(helper_busy), .data_out(read_data),
    .mem_request(mem_request), .mem_write(mem_write), .mem_address(mem_address),
    .mem_data(mem_data), .mem_done(mem_done), .mem_result(mem_result)
);

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
    wire [2:0] location = offset + position;
    assign display[27-position*7 -: 7] = location < visible ? glyphs[location] : 7'd0;
end endgenerate

always @(posedge clk) begin
    helper_request <= 0;
    if (helper_busy) saw_busy <= 1;
    if (tx_ready && remaining != 0) begin
        reply <= reply >> 8;
        remaining <= remaining - 1'b1;
    end
    if (visible > 4) begin
        if (timer == STEP_CYCLES - 1) begin
            timer <= 0;
            if (reverse) begin
                offset <= offset - 1'b1;
                if (offset == 1) reverse <= 0;
            end else begin
                offset <= offset + 1'b1;
                if (offset + 1 == visible - 4) reverse <= 1;
            end
        end else timer <= timer + 1'b1;
    end

    if (state != INPUT) begin
        if (saw_busy && !helper_busy) begin
            saw_busy <= 0;
            if (state == WRITE_WORD) begin
                stored <= stored + 1'b1;
                state <= INPUT;
            end else begin
                glyphs[index] <= glyph(read_data[7:0]);
                if (index + 1 == target) begin
                    visible <= target;
                    state <= INPUT;
                end else begin
                    index <= index + 1'b1;
                    helper_request <= 1;
                end
            end
        end
    end else if (can_reply) begin
        if (parity_error) begin
            reply <= 56'h25;
            remaining <= 1;
        end else if (valid && received == 8'h0d) begin
            reply <= 56'h485b1b4a325b1b;
            remaining <= 7;
            target <= stored;
            stored <= 0;
            visible <= 0;
            offset <= 0;
            reverse <= 0;
            timer <= 0;
            if (stored != 0) begin
                index <= 0;
                helper_request <= 1;
                state <= READ_WORD;
            end
        end else if (valid && received >= "0" && received <= "9" && stored < 7) begin
            reply <= {48'd0, received};
            remaining <= 1;
            symbol <= received;
            index <= stored;
            helper_request <= 1;
            state <= WRITE_WORD;
        end
    end
end
endmodule
