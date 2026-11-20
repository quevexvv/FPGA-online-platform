`timescale 1ns/1ps
// Capture five stable display frames in each of two UART phases.
module lab3_trace #(parameter SETTLE_CYCLES = 250000) (
    input wire clk, start_text, start_bad, finish_text,
    input wire [27:0] display,
    output reg [2:0] before_count = 0, after_count = 0,
    output reg [139:0] before_frames = 0, after_frames = 0
);
localparam IDLE = 0, BEFORE = 1, AFTER = 2, DONE = 3;
reg [1:0] phase = IDLE;
reg [27:0] candidate = 0;
reg [31:0] age = 0;

always @(posedge clk) begin
    if (phase == IDLE && start_text) phase <= BEFORE;
    else if (phase == BEFORE && start_bad) phase <= AFTER;
    else if (phase == AFTER && finish_text) phase <= DONE;

    if (display != candidate) begin
        candidate <= display;
        age <= 0;
    end else if (age < SETTLE_CYCLES) age <= age + 1'b1;
    else if (phase == BEFORE && !start_bad && before_count < 5 &&
             (before_count == 0 || candidate != before_frames[27:0])) begin
        before_frames <= {before_frames[111:0], candidate};
        before_count <= before_count + 1'b1;
    end else if (phase == AFTER && !finish_text && after_count < 5 &&
                 (after_count == 0 || candidate != after_frames[27:0])) begin
        after_frames <= {after_frames[111:0], candidate};
        after_count <= after_count + 1'b1;
    end
end
endmodule
