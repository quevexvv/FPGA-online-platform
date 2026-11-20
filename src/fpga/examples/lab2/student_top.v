module student_top (
    input wire clk,
    input wire reset,
    input wire [9:0] din,
    output reg [17:0] dout
);
    always @(posedge clk) begin
        if (reset)
            dout <= 18'h00001;
        else if (din[0])
            dout <= {dout[0], dout[17:1]};
        else
            dout <= {dout[16:0], dout[17]};
    end
endmodule
