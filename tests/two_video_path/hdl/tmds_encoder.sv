`timescale 1ns / 1ps
`default_nettype none

module tmds_encoder(
  input wire clk_in,
  input wire rst_in,
  input wire [7:0] data_in,  // video data (red, green or blue)
  input wire [1:0] control_in, //for blue set to {vs,hs}, else will be 0
  input wire ve_in,  // video data enable, to choose between control or video signal
  output logic [9:0] tmds_out
);

  logic [8:0] q_m;
  logic [4:0] tally; // twos complement
  logic [3:0] n1;
  logic [3:0] n0;
  
  tm_choice mtm(
    .data_in(data_in),
    .qm_out(q_m));

  always_comb begin
    n1 = 0;
    n0 = 0;
    for (integer i = 0; i < 8; i = i + 1) begin
      n1 = n1 + q_m[i];
      n0 = n0 + ~q_m[i];
    end
  end

  always_ff @(posedge clk_in) begin
    if (rst_in) begin
      tally <= 5'b0;
      tmds_out <= 10'b0;
    end else if (ve_in) begin 
      if ((tally == 5'b0) || (n1 == 4)) begin // if cnt(t-1) = 0 or n_1 = n_0
        tmds_out <= {~q_m[8], q_m[8], (q_m[8])? q_m[7:0] : ~q_m[7:0]};
        tally <= (q_m[8])? tally + n1 - n0 : 
                           tally + n0 - n1;
      end else if ((~tally[4] && (tally != 5'b0) && (n1 > n0)) || 
                   (tally[4] && n0 > n1)) begin
        tmds_out <= {1'b1, q_m[8], ~q_m[7:0]};
        tally <= tally +(q_m[8] << 1) + n0 - n1;
      end else begin
        tmds_out <= {1'b0, q_m[8], q_m[7:0]};
        tally <= tally - ((q_m[8])? 5'b00 : 5'b10) + n1 - n0;
      end
    end else begin
      tally <= 5'b0;
      case (control_in) 
        2'b00: tmds_out <= 10'b1101010100;
        2'b01: tmds_out <= 10'b0010101011;
        2'b10: tmds_out <= 10'b0101010100;
        2'b11: tmds_out <= 10'b1010101011;
      endcase
    end
  end

endmodule //end tmds_encoder
`default_nettype wire


