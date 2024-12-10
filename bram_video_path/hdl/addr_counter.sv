`default_nettype none
module addr_counter 
  #(
    parameter HCOUNT = 160,
    parameter VCOUNT = 90
  )
  ( input wire          clk_in,
    input wire          rst_in,
    input wire          evt_in,
    output logic[$clog2(HCOUNT)-1:0]  hcount_out,
    output logic [$clog2(VCOUNT)-1:0]        vcount_out
  );
  logic increment_vcount;
  spec_evt_counter # (
    .MAX_COUNT(HCOUNT)
  ) hcounter (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .evt_in(evt_in),
    .count_out(hcount_out),
    .hit_max_out_almost(increment_vcount)
  );
  spec_evt_counter # (
    .MAX_COUNT(VCOUNT)
  ) vcounter (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .evt_in(increment_vcount),
    .count_out(vcount_out)
  );
endmodule
`default_nettype wire