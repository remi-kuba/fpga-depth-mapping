`default_nettype none
module counter(     input wire clk_in,
                    input wire rst_in,
                    input wire [31:0] period_in,
                    output logic [31:0] count_out
              );

  always_ff @(posedge clk_in) begin
    count_out <= (rst_in || (count_out + 1 == period_in))? 0 : count_out + 1;
  end

endmodule

`default_nettype wire
