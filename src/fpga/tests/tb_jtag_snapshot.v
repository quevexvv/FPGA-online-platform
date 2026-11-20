`timescale 1ns/1ps

module tb_jtag_snapshot;
reg clk = 1'b0;
always #10 clk = ~clk;

reg request = 1'b0;
reg [7:0] counter = 8'h7c;
always @(posedge clk)
    counter <= counter + 1'b1;

wire [15:0] live = {counter, ~counter};
wire ack;
wire [15:0] snapshot;
jtag_snapshot #(.WIDTH(16)) dut (
    .clk(clk), .request(request), .live(live), .ack(ack), .snapshot(snapshot)
);

task capture_and_hold;
    input [7:0] cycles;
    reg [15:0] expected;
    integer index;
    begin
        @(negedge clk);
        expected = live;
        request = ~ack;
        @(negedge clk);
        if (snapshot !== expected || ack === request)
            $fatal(1, "Payload must be captured before acknowledgment");
        for (index = 0; index < cycles; index = index + 1) begin
            @(negedge clk);
            if (ack !== request || snapshot !== expected)
                $fatal(1, "Acknowledged snapshot must remain stable");
        end
    end
endtask

initial begin
    #1;
    if (ack !== 1'b0 || snapshot !== 16'd0)
        $fatal(1, "Unexpected initial handshake state");
    capture_and_hold(1);
    capture_and_hold(140);
    capture_and_hold(3);
    $display("PASS: atomic snapshot and repeated request acknowledgments");
    $finish;
end
endmodule
