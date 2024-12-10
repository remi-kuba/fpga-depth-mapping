`default_nettype none

module spi_send_con_2
#( parameter DATA_WIDTH = 8,
   parameter LINES = 1,
   parameter DATA_CLK_PERIOD = 100,
   parameter DUTY_CYCLE = DATA_CLK_PERIOD / 2,
   parameter DUTY_CYCLE_SIZE = $clog2(DUTY_CYCLE),
   parameter DATA_WIDTH_SIZE = $clog2(DATA_WIDTH + 1)
 )
 (input wire   clk_in, //system clock (100 MHz)
  input wire   rst_in, //reset in signal
  input wire   [DATA_WIDTH-1:0] data_in, //data to send
  input wire   trigger_in, //start a transaction
  input wire [10:0] hcount_in,
  input wire [9:0] vcount_in,
  input wire turn_off_cipo_in, // FOR DEBUGGING PURPOSES ADDED HERE

  output logic half_pixel_ready, // FOR DEBUGGING PURPOSES ADDED HERE
  output logic final_pixel_out,
  output logic [LINES-1:0] chip_data_out, // CIPO (this is the peripheral FPGA)
  output logic chip_clk_out, //(DCLK)
  output logic chip_sel_out // (CS)
 );
 
 logic [DUTY_CYCLE_SIZE-1:0] clk_count;
 logic [3:0] half_pixel;
//  logic half_pixel_ready;

 always_ff @(posedge clk_in) begin
    if (rst_in) begin
        // module should put 0's on all of its controllable outputs except for chip_sel_out
        chip_data_out <= 0;
        chip_sel_out <= 1'b1;
        chip_clk_out <= 1'b0;
        clk_count <= 0;
        half_pixel_ready <= 1'b0;
        half_pixel <= 4'b0;
        final_pixel_out <= 1'b0;
    end else if (trigger_in) begin 
        chip_clk_out <= 1'b0;
        chip_sel_out <= 1'b0; // Begin 
        chip_data_out <= (turn_off_cipo_in)? 4'b0 : data_in[7:4];
        half_pixel <= (turn_off_cipo_in)? 4'b0 : data_in[3:0];
        half_pixel_ready <= 1'b1;
        final_pixel_out <= (hcount_in == 1279) && (vcount_in == 719);
        // Reset 
        clk_count <= 0;
    end else begin
        if (!chip_sel_out) begin // Clock should only be running when CS is low
            clk_count <= clk_count + 1;
        end 

        if (clk_count == DUTY_CYCLE - 1) begin // Edge of the new clock
            clk_count <= 0; // Reset counter
            chip_clk_out <= ~chip_clk_out; // Make an edge

            if (chip_clk_out == 1'b1) begin // falling edge (1 -> 0)
                if (half_pixel_ready) begin
                    chip_data_out <= half_pixel;
                    half_pixel_ready <= 1'b0;
                    final_pixel_out <= 1'b0;
                end else begin
                    chip_sel_out <= 1'b1;
                end
            end 
        end
    end 

end

endmodule

`default_nettype wire
