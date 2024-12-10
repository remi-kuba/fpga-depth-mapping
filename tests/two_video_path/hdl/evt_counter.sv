`default_nettype none
module evt_counter 
  #(
    parameter MAX_COUNT
  )
  ( input wire          clk_in,
    input wire          rst_in,
    input wire          evt_in,
    output logic[$clog2(MAX_COUNT)-1:0]  count_out
  );
 
  always_ff @(posedge clk_in) begin
    if (rst_in || (count_out == MAX_COUNT - 1 && evt_in)) begin
      count_out <= 0;
    end else begin
      // If event is high, will add 1, else adds 0
      count_out <= count_out + evt_in;
    end
  end
endmodule
`default_nettype wire