`timescale 1ns / 1ps
`default_nettype none

module spi_receive_con
    #(  parameter DATA_WIDTH = 8,
        parameter LINES = 1,
        parameter DATA_CLK_PERIOD = 100,
        parameter DUTY_CYCLE = DATA_CLK_PERIOD / 2,
        parameter DUTY_CYCLE_SIZE = $clog2(DUTY_CYCLE),
        parameter DATA_WIDTH_SIZE = $clog2(DATA_WIDTH + 1)
    )
    (input wire   clk_in, //system clock (100 MHz)
     input wire   rst_in, //reset in signal
     output logic [DATA_WIDTH-1:0] data_out [LINES-1:0], // data received
     output logic data_valid_out, //high when output data is present.

     input wire   [LINES-1:0] chip_data_in, // CIPO (data being received from peripheral SPI)
     input wire chip_clk_in, //(DCLK)
     input wire chip_sel_in // (CS)
    );

    logic [DUTY_CYCLE_SIZE-1:0] clk_count;
    logic [DATA_WIDTH_SIZE-1:0] bits_received_count;
    logic prev_chip_clk;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            // module should put 0's on all of its controllable outputs except for chip_sel_out
            for (int line = 0; line < LINES; line++) begin
                data_out[line] <= 0;
            end
            data_valid_out <= 1'b0;
            bits_received_count <= 0;
            prev_chip_clk <= 1'b0;
        end else if (!chip_sel_in) begin // CS must be low to receive data
            prev_chip_clk <= chip_clk_in;
            if (~prev_chip_clk && chip_clk_in) begin// rising edge of DCLK (0 -> 1)
                // read data coming from cipo
                for (int line = 0; line < LINES; line++) begin
                    data_out[line] <= {data_out[line][DATA_WIDTH-2:0], chip_data_in[line]};
                end
                bits_received_count <= (bits_received_count == DATA_WIDTH - 1)? 0 : bits_received_count + 1;
            end
            data_valid_out <= ~prev_chip_clk && chip_clk_in && (bits_received_count == DATA_WIDTH - 1);
        end else data_valid_out <= 1'b0;
    end

endmodule

`default_nettype wire
