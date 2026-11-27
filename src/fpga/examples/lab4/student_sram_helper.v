`timescale 1ns/1ps
module student_sram_helper (
    input wire clk, request, write_word,
    input wire [17:0] address,
    input wire [15:0] data_in,
    output reg busy = 0,
    output reg [15:0] data_out = 0,
    output reg mem_request = 0, mem_write = 0,
    output reg [17:0] mem_address = 0,
    output reg [15:0] mem_data = 0,
    input wire mem_done,
    input wire [15:0] mem_result
);
always @(posedge clk) begin
    mem_request <= 0;
`ifdef LAB4_SHORT_BUSY
    if (busy) busy <= 0;
`endif
    if (!busy && request) begin
        busy <= 1;
        mem_request <= 1;
        mem_write <= write_word;
`ifdef LAB4_BAD_ADDRESS
        mem_address <= address == 18'h20000 ? 18'h00000 : address;
`else
        mem_address <= address;
`endif
`ifdef LAB4_BAD_DATA
        mem_data <= data_in ^ 16'h0001;
`else
        mem_data <= data_in;
`endif
    end else if (mem_done) begin
        if (!mem_write) data_out <= mem_result;
        busy <= 0;
    end
end
endmodule
