`timescale 1ns/1ps
module clock_board #(parameter PAUSE = 50000000, HALF_PERIOD = 25) (
    input wire clk,
    output wire [17:0] led
);
reg start = 0, reset_command = 0;
reg [15:0] steps = 0;
wire dut_clk, dut_reset, busy, done;
clock_burst #(.HALF_PERIOD(HALF_PERIOD)) generator (
    .clk(clk), .start(start), .reset_command(reset_command), .steps(steps),
    .dut_clk(dut_clk), .dut_reset(dut_reset), .busy(busy), .done(done)
);
// This independent counter sees actual generated clock edges.
reg [9:0] observed = 0;
always @(posedge dut_clk) begin
    if (dut_reset) observed <= 0;
    else observed <= observed + 1'b1;
end
reg [1:0] state = 0;
reg [3:0] phase = 0;
reg [25:0] delay_count = 0;
reg [9:0] expected = 0;
reg [9:0] snapshot = 0;
reg checked = 0, failed = 0;
reg [15:0] next_steps;
always @* begin
    next_steps = 0;
    if (phase == 2) next_steps = 1;
    else if (phase >= 3 && phase <= 11) next_steps = 16'b1 << (phase - 3);
end
always @(posedge clk) begin
    start <= 0;
    case (state)
        0: begin
            start <= 1;
            reset_command <= phase == 0;
            steps <= next_steps;
            expected <= phase == 0 ? 10'd0 : expected + next_steps[9:0];
            state <= 1;
        end
        1: if (done) begin
            // Whole-bus capture after the generator's low settling interval.
            if (observed != expected || busy || dut_clk) failed <= 1;
            snapshot <= observed;
            checked <= 1;
            delay_count <= 0;
            state <= 2;
        end
        2: begin
            if (observed != expected || busy || dut_clk) failed <= 1;
            if (delay_count == PAUSE - 1) begin
                delay_count <= 0;
                phase <= phase == 12 ? 4'd0 : phase + 1'b1;
                state <= 0;
            end else delay_count <= delay_count + 1'b1;
        end
        default: begin failed <= 1; state <= 2; end
    endcase
end
assign led = {6'b0, failed, checked && !failed, snapshot};
endmodule
