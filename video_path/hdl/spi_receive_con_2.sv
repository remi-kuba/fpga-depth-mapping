`timescale 1ns / 1ps
`default_nettype none

module spi_receive_con_2 # (
     parameter DATA_WIDTH = 8,
     parameter LINES = 4,
     parameter DATA_CLK_PERIOD = 6
    )
    (input wire   clk_in, //system clock (100 MHz)
     input wire   rst_in, //reset in signal
     output logic [DATA_WIDTH-1:0] data_out, // data received
     output logic data_valid_out, //high when output data is present.

     input wire   [LINES-1:0] chip_data_in, // CIPO (data being received from peripheral SPI)
     input wire chip_clk_in, //(DCLK)
     input wire chip_sel_in // (CS)
    );

    localparam DUTY_CYCLE = DATA_CLK_PERIOD / 2;
    localparam DUTY_CYCLE_SIZE = $clog2(DUTY_CYCLE);
    localparam DATA_WIDTH_SIZE = $clog2(DATA_WIDTH + 1);

    logic [DUTY_CYCLE_SIZE-1:0] clk_count;
    logic half_pixel_ready;
    logic prev_chip_clk;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            data_out <= 8'b0;
            data_valid_out <= 1'b0;
            prev_chip_clk <= 1'b0;
            half_pixel_ready <= 1'b0;
        end else if (!chip_sel_in) begin // CS must be low to receive data
            prev_chip_clk <= chip_clk_in;
            if (~prev_chip_clk && chip_clk_in) begin// rising edge of DCLK (0 -> 1)
                // read data coming from cipo
                data_out <= {data_out[3:0], chip_data_in};
                half_pixel_ready <= ~half_pixel_ready;
                data_valid_out <= half_pixel_ready;
            end else begin
                data_valid_out <= 1'b0;
            end
        end else data_valid_out <= 1'b0;
    end

endmodule

`default_nettype wire
