`timescale 1ns/1ps
module uart_commands #(parameter integer GAP_TICKS = 8680) (
    input wire clk, reset,
    input wire [7:0] rx_data,
    input wire rx_valid, framing_error,
    output wire [7:0] tx_data,
    output wire tx_valid,
    input wire tx_ready, tx_busy,
    output reg request = 0,
    output reg [7:0] command = 0,
    output reg [15:0] argument = 0,
    input wire done,
    input wire [17:0] snapshot
);
reg [47:0] frame = 0;
reg [2:0] length = 0;
reg [3:0] dropped = 0, pending_error = 0;
reg [31:0] gap = 0;
reg active = 0, query = 0, pending_reply = 0;
reg [63:0] reply = 0, sending = 0;
reg [3:0] remaining = 0;
function [4:0] unhex;
    input [7:0] c;
    begin
        if (c >= "0" && c <= "9") unhex = c - "0";
        else if (c >= "a" && c <= "f") unhex = c - "a" + 10;
        else unhex = 5'h10;
    end
endfunction
function [7:0] hexchar;
    input [3:0] v;
    begin hexchar = v < 10 ? "0" + v : "a" + v - 10; end
endfunction
function [63:0] response;
    input [7:0] kind;
    input [19:0] value;
    begin response = {8'h31, kind, hexchar(value[19:16]), hexchar(value[15:12]),
        hexchar(value[11:8]), hexchar(value[7:4]), hexchar(value[3:0]), 8'h0a}; end
endfunction
wire [4:0] h0 = unhex(frame[31:24]), h1 = unhex(frame[23:16]);
wire [4:0] h2 = unhex(frame[15:8]), h3 = unhex(frame[7:0]);
wire [15:0] value = {h0[3:0], h1[3:0], h2[3:0], h3[3:0]};
wire [7:0] op = frame[39:32];
wire [3:0] error_code = dropped != 0 ? dropped : length != 6 ? 4'd2 :
    frame[47:40] != "1" ? 4'd1 :
    (op != "R" && op != "I" && op != "S" && op != "Q") ? 4'd3 :
    (h0[4] || h1[4] || h2[4] || h3[4]) ? 4'd2 :
    ((op == "R" || op == "Q") && value != 0) || (op == "I" && value > 1023) ? 4'd4 :
    (active || pending_reply || pending_error != 0 || remaining != 0 || tx_busy) ? 4'd5 : 4'd0;
assign tx_data = sending[63:56];
assign tx_valid = remaining != 0;
always @(posedge clk) begin
    request <= 0;
    if (reset) begin
        frame <= 0; length <= 0; dropped <= 0; gap <= 0;
        pending_error <= 0; pending_reply <= 0; active <= 0;
        remaining <= 0; sending <= 0; reply <= 0; query <= 0;
        command <= 0; argument <= 0;
    end else begin
        if (active && done) begin
            reply <= response(query ? "D" : "K", query ? {2'b0, snapshot} : 20'd0);
            pending_reply <= 1;
            active <= 0;
        end
        if (remaining != 0 && tx_ready) begin
            sending <= {sending[55:0], 8'd0};
            remaining <= remaining - 1'b1;
        end else if (remaining == 0 && !tx_busy) begin
            if (pending_error != 0) begin
                sending <= response("E", {16'd0, pending_error});
                remaining <= 8;
                pending_error <= 0;
            end else if (pending_reply) begin
                sending <= reply;
                remaining <= 8;
                pending_reply <= 0;
            end
        end
        if (framing_error) begin
            dropped <= 6; length <= 0; gap <= 0;
        end else if (rx_valid) begin
            gap <= 0;
            if (rx_data == 8'h0a) begin
                length <= 0; dropped <= 0;
                if (error_code != 0) begin
                    if (pending_error == 0) pending_error <= error_code;
                end else begin
                    request <= 1; command <= op; argument <= value;
                    active <= 1; query <= op == "Q";
                end
            end else if (dropped == 0) begin
                if (length == 6) dropped <= 2;
                else begin frame <= {frame[39:0], rx_data}; length <= length + 1'b1; end
            end
        end else if (length != 0 || dropped != 0) begin
            if (gap == GAP_TICKS - 1) begin length <= 0; dropped <= 0; gap <= 0; end
            else gap <= gap + 1'b1;
        end
    end
end
endmodule
