`default_nettype none
module spi_evt_counter 
  #(
    parameter MAX_COUNT = 6
  )
  ( input wire          clk_in,
    input wire          rst_in,
    input wire          evt_in,
    output logic[$clog2(MAX_COUNT)-1:0]  count_out,
    output logic        hit_max_out
  );
  // logic[$clog2(MAX_COUNT)-1:0]  count_out;
  
  always_ff @(posedge clk_in) begin
    if (rst_in) begin
      count_out <= 0;
      hit_max_out <= 1'b0;
    end else if (count_out == MAX_COUNT - 1 && evt_in) begin
      count_out <= 0;
      hit_max_out <= 1'b1;
    end else begin
      // If event is high, will add 1, else adds 0
      count_out <= count_out + evt_in;
      hit_max_out <= 1'b0;
    end
  end
endmodule
`default_nettype wire