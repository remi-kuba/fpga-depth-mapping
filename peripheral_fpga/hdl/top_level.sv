`timescale 1ns / 1ps
`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module top_level(
  input wire clk_100mhz, //100 MHz onboard clock
  // input wire [15:0] sw, //all 16 input slide switches
  input wire [3:0] btn, //all four momentary button switches

  // SPI 
  output logic dclk, // data clock output of SPI controller
  output logic [3:0] cipo, // six parallel data outputs of SPI controller
  output logic cs, // chip select line for the SPI bus
  output logic spi_hsync,
  output logic spi_vsync,

  // Camera
  input wire [7:0]    camera_d, // 8 parallel data wires
  output logic        cam_xclk, // XC driving camera
  input wire          cam_hsync, // camera hsync wire
  input wire          cam_vsync, // camera vsync wire
  input wire          cam_pclk, // camera pixel clock
  inout wire          i2c_scl, // i2c inout clock
  inout wire          i2c_sda // i2c inout data
  );

  /*
    RESETS
  */
  // btn[0] controls system reset
  logic sys_rst;
  assign sys_rst = btn[0];

  /*
    CLOCKS
  */

  logic clk_camera; // 200 MHz
  logic clk_pixel; // 74.25 MHz
  // Middle clocks
  logic clk_100_passthrough;
  logic clk_5x;
  logic clk_xc;
  cw_hdmi_clk_wiz wizard_hdmi
    (.sysclk(clk_100_passthrough),
     .clk_pixel(clk_pixel),
     .clk_tmds(clk_5x),
     .reset(0));

  cw_fast_clk_wiz wizard_migcam
    (.clk_in1(clk_100mhz),
     .clk_camera(clk_camera),
     .clk_xc(clk_xc),
     .clk_100(clk_100_passthrough),
     .reset(0));
  
  // assign camera's xclk to pmod port: drive the operating clock of the camera!
  // this port also is specifically set to high drive by the XDC file.
  assign cam_xclk = clk_xc;
  

  

  /*
    CAMERA 
  */

  // synchronizers to prevent metastability
  logic [7:0]    camera_d_buf [1:0];
  logic          cam_hsync_buf [1:0];
  logic          cam_vsync_buf [1:0];
  logic          cam_pclk_buf [1:0];

  always_ff @(posedge clk_camera) begin
     camera_d_buf <= {camera_d, camera_d_buf[1]};
     cam_pclk_buf <= {cam_pclk, cam_pclk_buf[1]};
     cam_hsync_buf <= {cam_hsync, cam_hsync_buf[1]};
     cam_vsync_buf <= {cam_vsync, cam_vsync_buf[1]};
  end



  /*
    PIXEL RECONSTRUCT (clk_camera, 200 MHz)
  */

  logic [9:0] camera_hcount;
  logic [8:0] camera_vcount;
  logic [7:0] camera_pixel;
  logic       camera_valid;
  logic       camera_hsync;
  logic       camera_vsync;

  luminance_reconstruct #(
    // Camera output: 640 x 360, not 1280 x 720
    .HCOUNT_WIDTH(10),
    .VCOUNT_WIDTH(9)
  ) lr_mod 
  (.clk_in(clk_camera),
   .rst_in(sys_rst),
   .camera_pclk_in(cam_pclk_buf[0]),
   .camera_hs_in(cam_hsync_buf[0]),
   .camera_vs_in(cam_vsync_buf[0]),
   .camera_data_in(camera_d_buf[0]),
   .pixel_valid_out(camera_valid),
   .pixel_hcount_out(camera_hcount),
   .pixel_vcount_out(camera_vcount),
   .pixel_data_out(camera_pixel),
   .hsync_out(camera_hsync),
   .vsync_out(camera_vsync));


  /*
    CDC (clk_camera 200 Mhz -> clk_100_passthrough 100 MHz)
  */
  logic empty;
  logic [7:0] cdc_pixel;
  logic [10:0] cdc_hcount;
  logic [9:0] cdc_vcount;
  logic cdc_hsync;
  logic cdc_vsync;
  logic cdc_cam_valid;

  fifo cdc_fifo
    (.wr_clk(clk_camera),
     .full(),
     .din({camera_hcount, camera_vcount, camera_pixel, camera_valid, camera_hsync, camera_vsync}),
     .wr_en(1), // always write, even when in the syncing periods

     .rd_clk(clk_100_passthrough),
     .empty(empty),
     .dout({cdc_hcount, cdc_vcount, cdc_pixel, cdc_cam_valid, cdc_hsync, cdc_vsync}),
     .rd_en(1) //always read
    );

  assign should_pack = ~empty && cdc_cam_valid; //watch when empty. Ready immediately if something there  logic should_pack;

  /*
    SPI CONVERSION (clk_100mhz, 100 MHz)
    Want to send 4 pixels at a time through 6 lines
    Other two lines: hcount, vcount
    Length of each package: 10 bits (hcount is bottleneck of 10 bits)
  */

  logic [7:0] pixels_to_send [3:0];

  // Want to send corresponding hsync and vsync wires in parallel with SPI
  assign spi_hsync = ~empty && cdc_hsync;
  assign spi_vsync = ~empty && cdc_vsync;


  // Packing logic for sending four pixels at a time
  always_ff @(posedge clk_100_passthrough) begin
    if (should_pack) begin
      pixels_to_send[count_out] <= cdc_pixel;
    end
  end

  logic packet_ready;
  logic[1:0]  count_out;
  evt_counter #(
    .MAX_COUNT(4)
  ) packet_ready_counter (
    .clk_in(clk_100_passthrough),
    .rst_in(sys_rst),
    .evt_in(should_pack),
    .count_out(count_out),
    .hit_max(packet_ready)
  );

  spi_send_con # (
    .DATA_WIDTH(8), // each line should send the 8 bit luminance
    .LINES(4), // four parallel lines
    .DATA_CLK_PERIOD(6) // 16.6 MHz SPI Clock
  ) spi_send (
    .clk_in(clk_100_passthrough),
    .rst_in(sys_rst),
    .data_in(pixels_to_send), // LINES arrays of length DATA_WIDTH bits
    .trigger_in(packet_ready),

    .chip_data_out(cipo), // 6 bits (1 bit from each of the 6 pixels)
    .chip_clk_out(dclk),
    .chip_sel_out(cs),
  );

 
endmodule // top_level

`default_nettype wire