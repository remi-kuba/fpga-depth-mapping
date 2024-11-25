// `timescale 1ns / 1ps
`default_nettype none


module sad (
    input wire clk_in,
    input wire rst_in,
    input wire [KERNEL_SIZE-1:0][7:0] data_cam1,
    input wire [KERNEL_SIZE-1:0][7:0] data_cam2,
    input wire [10:0] hcount_in,
    input wire [9:0] vcount_in,
    input wire data_valid_in,
    output logic data_valid_out,
    output logic [10:0] hcount_out,
    output logic [9:0] vcount_out,
    output logic [7:0] line_out
    );

    localparam KERNEL_SIZE = 3;
    localparam OFFSET = 10;

    logic signed [KERNEL_SIZE-1:0][KERNEL_SIZE-1:0][7:0] coeffs;

    always_ff @(posedge clk_in) begin
        if (data_valid_in) begin
        end
    end

endmodule

`default_nettype wire

