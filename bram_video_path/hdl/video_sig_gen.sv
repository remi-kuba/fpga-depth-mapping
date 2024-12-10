`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module video_sig_gen
#(
  parameter ACTIVE_H_PIXELS = 1280,
  parameter H_FRONT_PORCH = 110,
  parameter H_SYNC_WIDTH = 40,
  parameter H_BACK_PORCH = 220,
  parameter ACTIVE_LINES = 720,
  parameter V_FRONT_PORCH = 5,
  parameter V_SYNC_WIDTH = 5,
  parameter V_BACK_PORCH = 20,
  parameter FPS = 60)
(
  input wire pixel_clk_in,
  input wire rst_in,
  output logic [$clog2(TOTAL_COLS)-1:0] hcount_out,
  output logic [$clog2(TOTAL_LINES)-1:0] vcount_out,
  output logic vs_out, //vertical sync out
  output logic hs_out, //horizontal sync out
  output logic ad_out,
  output logic nf_out, //single cycle enable signal
  output logic [5:0] fc_out); //frame

  localparam V_SYNC_START = ACTIVE_LINES + V_FRONT_PORCH;
  localparam TOTAL_LINES = V_SYNC_START + V_SYNC_WIDTH + V_BACK_PORCH;
  localparam H_SYNC_START = ACTIVE_H_PIXELS + H_FRONT_PORCH;
  localparam TOTAL_COLS = H_SYNC_START+ H_SYNC_WIDTH + H_BACK_PORCH;
  localparam TOTAL_PIXELS = TOTAL_LINES * TOTAL_COLS; 

  always_ff @(posedge pixel_clk_in) begin

    if (rst_in) begin // reset all outputs to 0

      hcount_out <= 0;
      vcount_out <= 0;
      vs_out <= 1'b0;
      hs_out <= 1'b0;
      ad_out <= 1'b0;
      nf_out <= 1'b0;
      fc_out <= 6'b0;

    end else if (hcount_out + 1 == TOTAL_COLS) begin // going on to next row

      hcount_out <= 0;

      if (vcount_out + 1 == TOTAL_LINES) begin
        vcount_out <= 0;
        fc_out <= (fc_out + 1 == FPS)? 6'b0 : fc_out + 1;
        ad_out <= 1'b1;
      end else begin
        vcount_out <= vcount_out + 1;
        ad_out <= (vcount_out + 1 < ACTIVE_LINES);
      end

      if ((vcount_out + 1 == V_SYNC_START) ||
          (vs_out && vcount_out + 1 == V_SYNC_START + V_SYNC_WIDTH)) begin
        vs_out <= ~vs_out;
      end
    end else begin

      hcount_out <= hcount_out + 1;
      ad_out <= ((vcount_out < ACTIVE_LINES) && (hcount_out + 1 < ACTIVE_H_PIXELS));
      nf_out <= (hcount_out + 1 == ACTIVE_H_PIXELS) && (vcount_out == ACTIVE_LINES); 
      
      if ((hcount_out + 1 == H_SYNC_START) ||
                   (hs_out && hcount_out + 1 == H_SYNC_START + H_SYNC_WIDTH)) begin
        hs_out <= ~hs_out;
      end 

    end

  end

endmodule

`default_nettype wire