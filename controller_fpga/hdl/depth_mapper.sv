`default_nettype none

module filter (
  input wire clk_in,
  input wire rst_in,

  input wire data_cam1_valid,
  input wire data_cam2_valid,
  input wire [7:0] cam1_pixel_data,
  input wire [7:0] cam2_pixel_data,
  input wire [10:0] hcount_in1,
  input wire [10:0] hcount_in2,
  input wire [9:0] vcount_in1,
  input wire [9:0] vcount_in2,

  output logic data_valid_out,
  output logic [15:0] pixel_data_out,
  output logic [10:0] hcount_out,
  output logic [9:0] vcount_out
  );

  parameter HRES = 640;
  parameter VRES = 360;
  parameter OFFSET = 10;
  localparam KERNEL_WIDTH = 3;

  logic [KERNEL_WIDTH-1:0][7:0] Lbuffs;
  logic [KERNEL_WIDTH-1:0][7:0] Rbuffs;
  logic b_to_s_valid;
  //have to add more stuff here:
  logic [10:0] hcount_buff; //hard code like a loser whatever
  logic [9:0] vcount_buff;

    //TODO: Add FIFOs? align with the hcount/vcount values

  line_buffer #(.HRES(HRES),
                .VRES(VRES))
    left_lbuff (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .data_valid_in(data_cam1_valid),
    .pixel_data_in(cam1_pixel_data),
    .hcount_in(hcount_in1),
    .vcount_in(vcount_in2),
    .data_valid_out(b_to_s_valid),
    .line_buffer_out(Lbuffs),
    .hcount_out(hcount_buff),
    .vcount_out(vcount_buff)
    );

  line_buffer #(.HRES(HRES),
                .VRES(VRES))
    right_lbuff (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .data_valid_in(data_cam2_valid),
    .pixel_data_in(cam2_pixel_data),
    .hcount_in(hcount_in1),
    .vcount_in(vcount_in2),
    .data_valid_out(b_to_s_valid),
    .line_buffer_out(Rbuffs),
    .hcount_out(hcount_buff),
    .vcount_out(vcount_buff)
    );


sad #(.KERNEL_WIDTH(3), .OFFSET(10)) sadCalc(
    .clk_in(clk_in), .rst_in(rst_in), .left_data_in(), .right_data_in(),
    .hcount_in(), .vcount_in(), .data_valid_in(b_to_s_valid),
    .data_valid_out(data_valid_out), 
    .busy_out(), // whether it is still calculating a module
    .hcount_out(hcount_out), .vcount_out(vcount_out), 
    .line_out(pixel_depth_out), // relative depth
    .offset_out(), // FOR TESTING PURPOSES
    .diffs_out () // FOR TESTING PURPOSES
    );

//   convolution #(
//     .K_SELECT(K_SELECT) )
//     mconv (
//     .clk_in(clk_in),
//     .rst_in(rst_in),
//     .data_in(buffs),
//     .data_valid_in(b_to_c_valid),
//     .hcount_in(hcount_buff),
//     .vcount_in(vcount_buff),
//     .line_out(pixel_data_out),
//     .data_valid_out(data_valid_out),
//     .hcount_out(hcount_out),
//     .vcount_out(vcount_out)
//   );

endmodule

`default_nettype wire