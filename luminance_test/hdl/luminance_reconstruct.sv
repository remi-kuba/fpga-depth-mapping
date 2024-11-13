`timescale 1ns / 1ps
`default_nettype none

module luminance_reconstruct
	#(
	 parameter HCOUNT_WIDTH = 11,
	 parameter VCOUNT_WIDTH = 10
	 )
	(
	 input wire 										 clk_in,
	 input wire 										 rst_in,
	 input wire 										 camera_pclk_in,
	 input wire 										 camera_hs_in,
	 input wire 										 camera_vs_in,
	 input wire [7:0] 							 camera_data_in,
	 output logic 									 pixel_valid_out,
	 output logic [HCOUNT_WIDTH-1:0] pixel_hcount_out,
	 output logic [VCOUNT_WIDTH-1:0] pixel_vcount_out,
	 output logic [7:0] 						 pixel_data_out,
	 output logic hsync_out,
	 output logic vsync_out
	 );

	 
	 // previous value of PCLK
	 logic 													 pclk_prev;

	 // can be assigned combinationally:
	 //  true when pclk transitions from 0 to 1
	 logic 													 camera_sample_valid;
	 assign camera_sample_valid = ~pclk_prev && camera_pclk_in;
	 
	 // previous value of camera data, from last valid sample!
	 // should NOT update on every cycle of clk_in, only
	 // when samples are valid.
	 logic 													 last_sampled_hs;
	 logic [7:0] 										 last_sampled_data;

	 // flag indicating whether the last byte has been transmitted or not.
	 logic 													 half_pixel_ready;

	 always_ff@(posedge clk_in) begin
			pclk_prev <=  camera_pclk_in; // update the clock value	

			if (rst_in) begin
				pixel_valid_out <= 1'b0;
				pixel_hcount_out <= -1;
				pixel_vcount_out <= 0;
				pixel_data_out <= 16'b0;
				hsync_out <= 1'b0;
				vsync_out <= 1'b0;
				half_pixel_ready <= 1'b0;
				last_sampled_hs <= 1'b0;
				last_sampled_data <= 8'b0;
            end else if (camera_sample_valid) begin
                pixel_valid_out <= (camera_hs_in && camera_vs_in);
                hsync_out <= camera_hs_in;
                vsync_out <= camera_vs_in;

                pixel_data_out <= camera_data_in;
                pixel_hcount_out <= (camera_hs_in && camera_vs_in)? pixel_hcount_out + 1 : -1;
                pixel_vcount_out <= (!camera_vs_in)? 0 : 
                                    (!camera_hs_in && last_sampled_hs)? pixel_vcount_out + 1 :
                                                                        pixel_vcount_out;
                
                last_sampled_hs <= camera_hs_in;
            end else begin
                pixel_valid_out <= 1'b0;
            end
	 end
	 
endmodule

`default_nettype wire
