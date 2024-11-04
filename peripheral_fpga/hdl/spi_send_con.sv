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

  output logic [5:0] chip_data_out, // COPI, 6 parallel lines
  output logic chip_clk_out, //(DCLK)
  output logic chip_sel_out // (CS)
 );

 logic [DUTY_CYCLE_SIZE-1:0] counter;
 logic [DATA_WIDTH-1:0] copi_data;
 logic [DATA_WIDTH-1:0] cipo_data;
 logic [DATA_WIDTH_SIZE-1:0] bits_received_counter;

 always_ff @(posedge clk_in) begin
    if (data_valid_out == 1'b1) begin
        data_valid_out <= 1'b0;
    end

    if (rst_in) begin
        // module should put 0's on all of its controllable outputs except for chip_sel_out
        // data_out <= 0;
        data_valid_out <= 1'b0;
        chip_data_out <= 1'b0;
        chip_sel_out <= 1'b1;
        chip_clk_out <= 1'b0;
        data_out <= 0;
    end else if (trigger_in) begin 
        chip_sel_out <= 1'b0; // Begin

        copi_data = data_in; // Save data_in bits before they disappear
        chip_data_out <= copi_data[DATA_WIDTH - 1]; // Send first bit of data_in
        copi_data = copi_data << 1;
        // Reset
        cipo_data <= 0;
        counter <= 0;
        bits_received_counter <= 0;
    end else begin
        if (!chip_sel_out) begin // Clock should only be running when CS is low
            counter <= counter + 1;
        end 

        if (counter == DUTY_CYCLE - 1) begin // Edge of the new clock
            counter <= 0; // Reset counter
            chip_clk_out <= ~chip_clk_out; // Make an edge

            if (chip_clk_out == 1'b1) begin // falling edge (1 -> 0)
                if (bits_received_counter == DATA_WIDTH) begin // Sending/receiving is done
                    chip_sel_out <= 1'b1;
                    // Post the data received
                    data_valid_out <= 1'b1;
                    data_out <= cipo_data;
                end else begin
                    // Next bit of copi
                    chip_data_out <= copi_data[DATA_WIDTH - 1];
                    copi_data = copi_data << 1;
                end
            end else begin // rising edge (0 -> 1)
                // Read bit of cipo
                cipo_data <= {cipo_data[DATA_WIDTH-2:0], chip_data_in};
                bits_received_counter <= bits_received_counter + 1;
            end

        end
    end 

end

endmodule

`default_nettype wire
