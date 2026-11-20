`timescale 1ns/1ps
module lab3_uart_probe #(parameter integer CLKS_PER_BIT = 434) (
    input wire clk,
    input wire rx,
    output wire tx
);
wire [7:0] received;
wire valid, parity_error, ready;
reg pending = 0;
reg [7:0] reply = 0;
reg [2:0] accepted = 0;

uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT), .EVEN_PARITY(1)) receiver (
    .clk(clk), .reset(1'b0), .rx(rx), .data(received), .valid(valid),
    .framing_error(), .parity_error(parity_error)
);
uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT), .EVEN_PARITY(1)) transmitter (
    .clk(clk), .reset(1'b0), .data(reply), .valid(pending),
    .ready(ready), .tx(tx), .busy()
);

// One reply per complete frame. The transmitter can consume the previous
// reply on the same edge that the receiver queues the next one.
always @(posedge clk) begin
    if (ready) pending <= 0;
    if ((valid || parity_error) && (!pending || ready)) begin
        pending <= 1;
        if (parity_error) reply <= 8'h25; // '%'
        else if (received == 8'h0d) begin
            reply <= 8'h30 + {5'b0, accepted};
            accepted <= 0;
        end else if (accepted == 4) reply <= 8'h21; // '!'
        else begin
            reply <= received;
            accepted <= accepted + 1'b1;
        end
    end
end
endmodule
