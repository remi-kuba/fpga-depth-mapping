`default_nettype none
module bram_counter 
  #(
    parameter MAX_COUNT = 12,
    parameter READ_COUNT = MAX_COUNT - 2
  )
  ( input wire          clk_in,
    input wire          rst_in,
    output logic hit_max_out,
    output logic read_request_out
  );

  logic[$clog2(MAX_COUNT)-1:0]  count_out;

  always_ff @(posedge clk_in) begin
    if (rst_in) begin
        count_out <= 0;
        hit_max_out <= 1'b0;
        read_request_out <= 1'b0;
    end else begin
        count_out <= (count_out == MAX_COUNT - 1)? 0 : count_out + 1;
        hit_max_out <= (count_out == MAX_COUNT - 1);
        read_request_out <= (count_out == READ_COUNT - 1);
    end
  end
endmodule
`default_nettype wire