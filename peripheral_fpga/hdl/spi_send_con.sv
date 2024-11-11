`timescale 1ns / 1ps
`default_nettype none

module spi_send_con
#( parameter DATA_WIDTH = 8,
   parameter LINES = 1,
   parameter DATA_CLK_PERIOD = 100,
   parameter DUTY_CYCLE = DATA_CLK_PERIOD / 2,
   parameter DUTY_CYCLE_SIZE = $clog2(DUTY_CYCLE),
   parameter DATA_WIDTH_SIZE = $clog2(DATA_WIDTH + 1)
 )
 (input wire   clk_in, //system clock (100 MHz)
  input wire   rst_in, //reset in signal
  input wire   [LINES-1:0][DATA_WIDTH-1:0] data_in, //data to send
  input wire   trigger_in, //start a transaction

  output logic [LINES-1:0] chip_data_out, // CIPO (this is the peripheral FPGA)
  output logic chip_clk_out, //(DCLK)
  output logic chip_sel_out // (CS)
 );

 logic [DUTY_CYCLE_SIZE-1:0] clk_count;
 logic [LINES-1:0][DATA_WIDTH-2:0] cipo_data;
 logic [DATA_WIDTH_SIZE-1:0] bits_sent_counter;

 always_ff @(posedge clk_in) begin
    if (data_valid_out == 1'b1) begin
        data_valid_out <= 1'b0;
    end

    if (rst_in) begin
        // module should put 0's on all of its controllable outputs except for chip_sel_out
        data_valid_out <= 1'b0;
        chip_data_out <= 0;
        chip_sel_out <= 1'b1;
        chip_clk_out <= 1'b0;
        data_out <= 0;
    end else if (trigger_in) begin 
        chip_sel_out <= 1'b0; // Begin 

        for (int line = 0; line < LINES; line++) begin
            // Send first bit of data_in for each line
            chip_data_out[line] <= data_in[line][DATA_WIDTH - 1]; 

            // Save rest of data_in bits before they disappear
            // Note: don't need to save top most bit since already sending out
            cipo_data[line] <= data_in[line][DATA_WIDTH-2:0];
        end 

        // Reset 
        clk_count <= 0;
        bits_sent_counter <= 0;
    end else begin
        if (!chip_sel_out) begin // Clock should only be running when CS is low
            clk_count <= clk_count + 1;
        end 

        if (clk_count == DUTY_CYCLE - 1) begin // Edge of the new clock
            clk_count <= 0; // Reset counter
            chip_clk_out <= ~chip_clk_out; // Make an edge

            if (chip_clk_out == 1'b1) begin // falling edge (1 -> 0)
                if (bits_sent_counter == DATA_WIDTH) begin // Sending is done
                    chip_sel_out <= 1'b1;
                end else begin 
                    // Next bits of cipo sending
                    for (int line = 0; line < LINES; line++) begin
                        chip_data_out[line] <= cipo_data[line][DATA_WIDTH - 1];
                        cipo_data[line] <= cipo_data[line] << 1;
                    end
                end
            end else begin // rising edge (0 -> 1)
                bits_sent_counter <= bits_sent_counter + 1;
            end
        end
    end 

end

endmodule

`default_nettype wire
