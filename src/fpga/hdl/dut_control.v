`timescale 1ns/1ps
module dut_control #(parameter integer HALF_PERIOD = 25) (
    input wire clk, reset, request,
    input wire [7:0] command,
    input wire [15:0] argument,
    input wire [17:0] dout,
    output reg [9:0] din = 0,
    output wire dut_clk, dut_reset,
    output reg done = 0,
    output reg [17:0] snapshot = 0
);
localparam IDLE = 0, WAIT_CLOCK = 1, SETTLE = 2;
reg [1:0] state = IDLE;
reg start = 0, reset_command = 0;
reg [15:0] steps = 0;
reg [31:0] delay_count = 0;
wire clock_done;
clock_burst #(.HALF_PERIOD(HALF_PERIOD)) generator (
    .clk(clk), .reset(reset), .start(start), .reset_command(reset_command), .steps(steps),
    .dut_clk(dut_clk), .dut_reset(dut_reset), .busy(), .done(clock_done));
always @(posedge clk) begin
    start <= 0;
    done <= 0;
    if (reset) begin
        state <= IDLE; din <= 0; snapshot <= 0;
        delay_count <= 0; reset_command <= 0; steps <= 0;
    end else case (state)
        IDLE: if (request) begin
            if (command == "R" || command == "S") begin
                reset_command <= command == "R";
                steps <= argument;
                start <= 1;
                state <= WAIT_CLOCK;
            end else begin
                if (command == "I") din <= argument[9:0];
                delay_count <= HALF_PERIOD - 1;
                state <= SETTLE;
            end
        end
        WAIT_CLOCK: if (clock_done) begin
            // The generated clock has stopped and completed its low settling interval.
            snapshot <= dout; done <= 1; state <= IDLE;
        end
        SETTLE: if (delay_count != 0) delay_count <= delay_count - 1'b1;
        else begin snapshot <= dout; done <= 1; state <= IDLE; end
        default: state <= IDLE;
    endcase
end
endmodule
