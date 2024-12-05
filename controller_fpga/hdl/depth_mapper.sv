`default_nettype none

module depth_mapper (
  input wire clk_in, //100 MHz
  input wire rst_in,

  input wire data_cam1_valid,
  input wire data_cam2_valid,
  input wire [7:0] cam1_pixel_data,
  input wire [7:0] cam2_pixel_data,
  input wire [10:0] hcount_in,
  input wire [9:0] vcount_in,

  output logic data_valid_out,
  output logic [7:0] pixel_depth_out,
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


  line_buffer #(.HRES(HRES),
                .VRES(VRES))
    left_lbuff (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .data_valid_in(data_cam1_valid),
    .pixel_data_in(cam1_pixel_data),
    .hcount_in(hcount_in),
    .vcount_in(vcount_in),
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
    .hcount_in(hcount_in),
    .vcount_in(vcount_in),
    .data_valid_out(b_to_s_valid),
    .line_buffer_out(Rbuffs),
    .hcount_out(hcount_buff),
    .vcount_out(vcount_buff)
    );


sad #(.KERNEL_WIDTH(3), .OFFSET(10)) sadCalc(
    .clk_in(clk_in), .rst_in(rst_in), .left_data_in(), .right_data_in(),
    .hcount_in(hcount_in), .vcount_in(vcount_in), .data_valid_in(b_to_s_valid),
    .data_valid_out(data_valid_out), 
    .busy_out(), // whether it is still calculating a module
    .hcount_out(hcount_out), .vcount_out(vcount_out), 
    .line_out(pixel_depth_out), // relative depth
    .offset_out(), // FOR TESTING PURPOSES
    .diffs_out () // FOR TESTING PURPOSES
    );


endmodule

`default_nettype wire
