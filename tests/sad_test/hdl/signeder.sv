`timescale 1ns / 1ps
`default_nettype none

module signeder (
    input wire clk_in,
    input wire rst_in,
    input wire [4:0] a_in,
    input wire [4:0] b_in,
    output logic compare_out
);

    always_ff @(posedge clk_in) begin
        if (rst_in) begin 
            compare_out <= 1'b0;
        end else begin
            compare_out <= (a_in < b_in);
        end
    end


endmodule
`default_nettype wire