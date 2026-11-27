`timescale 1ns/1ps
module c5g_sram_word (
    input wire clk, start, write_word,
    input wire [17:0] address,
    input wire [15:0] write_data,
    output reg done = 0,
    output reg [15:0] read_data = 0,
    output reg [17:0] sram_a = 0,
    inout wire [15:0] sram_d,
    output reg ce_n = 1, oe_n = 1, we_n = 1,
    output wire lb_n, ub_n
);
localparam IDLE = 0, SETUP = 1, ACCESS = 2, HOLD = 3;
reg [1:0] state = IDLE;
reg [2:0] delay_cycles = 0;
reg [15:0] data_out = 0;
reg drive = 0;
assign sram_d = drive ? data_out : 16'bz;
assign lb_n = ce_n;
assign ub_n = ce_n;

// At 50 MHz: 60 ns setup, 100 ns access, 60 ns hold/turnaround.
always @(posedge clk) begin
    done <= 0;
    if (state == IDLE) begin
        if (start) begin
            sram_a <= address;
            data_out <= write_data;
            drive <= write_word;
            ce_n <= 0;
            state <= SETUP;
            delay_cycles <= 2;
        end
    end else if (delay_cycles != 0) begin
        delay_cycles <= delay_cycles - 1'b1;
    end else begin
        case (state)
            SETUP: begin
                oe_n <= drive;
                we_n <= !drive;
                state <= ACCESS;
                delay_cycles <= 4;
            end
            ACCESS: begin
                if (!drive) read_data <= sram_d;
                oe_n <= 1;
                we_n <= 1;
                state <= HOLD;
                delay_cycles <= 2;
            end
            HOLD: begin
                drive <= 0;
                ce_n <= 1;
                done <= 1;
                state <= IDLE;
            end
            default: state <= IDLE;
        endcase
    end
end
endmodule
