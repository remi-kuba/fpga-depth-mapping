`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module top_level(
  input wire clk_100mhz, //100 MHz onboard clock
  input wire [15:0] sw, //all 16 input slide switches
  input wire [3:0] btn, //all four momentary button switches

  // SPI 
  output logic dclk, // data clock output of SPI controller
  output logic [5:0] copi, // six parallel data outputs of SPI controller
  output logic cs, // chip select line for the SPI bus

  // Camera
  input wire [7:0]    camera_d, // 8 parallel data wires
  output logic        cam_xclk, // XC driving camera
  input wire          cam_hsync, // camera hsync wire
  input wire          cam_vsync, // camera vsync wire
  input wire          cam_pclk, // camera pixel clock
  inout wire          i2c_scl, // i2c inout clock
  inout wire          i2c_sda, // i2c inout data
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

  logic [10:0] camera_hcount;
  logic [9:0]  camera_vcount;
  logic [15:0] camera_pixel;
  logic        camera_valid;

  pixel_reconstruct
  (.clk_in(clk_camera),
   .rst_in(sys_rst_camera),
   .camera_pclk_in(cam_pclk_buf[0]),
   .camera_hs_in(cam_hsync_buf[0]),
   .camera_vs_in(cam_vsync_buf[0]),
   .camera_data_in(camera_d_buf[0]),
   .pixel_valid_out(camera_valid),
   .pixel_hcount_out(camera_hcount),
   .pixel_vcount_out(camera_vcount),
   .pixel_data_out(camera_pixel));


  /*
    CDC (clk_camera 200 Mhz -> clk_pixel 74.25 MHz)
  */
  logic
   empty;
  logic cdc_valid;
  logic [15:0] cdc_pixel;
  logic [10:0] cdc_hcount;
  logic [9:0] cdc_vcount;

  fifo cdc_fifo
    (.wr_clk(clk_camera),
     .full(),
     .din({camera_hcount, camera_vcount, camera_pixel}),
     .wr_en(camera_valid),

     .rd_clk(clk_pixel),
     .empty(empty),
     .dout({cdc_hcount, cdc_vcount, cdc_pixel}),
     .rd_en(1) //always read
    );

  assign cdc_valid = ~empty; //watch when empty. Ready immediately if something there



  /*
    LINE BUFFER (clk_pixel, 74.25 MHz) + 
    ANTI-ALIASING GAUSSIAN BLUR (clk_pixel, 74.25 MHz)
  */

  logic [10:0] blur_hcount;  //hcount from blur module
  logic [9:0] blur_vcount; //vcount from blur module
  logic [15:0] blur_pixel; //pixel data from blur module
  logic blur_valid; //valid signals for blur module
  //full resolution filter
  blur_filter #(.HRES(1280),.VRES(720))
    blur(
    .clk_in(clk_pixel), 
    .rst_in(sys_rst_pixel),
    .data_valid_in(cdc_valid),
    .pixel_data_in(cdc_pixel), // 16 bits
    .hcount_in(cdc_hcount), // 11 bits
    .vcount_in(cdc_vcount), // 10 bits
    .data_valid_out(blur_valid), 
    .pixel_data_out(blur_pixel), // 16 bits
    .hcount_out(blur_hcount), // 11 bits
    .vcount_out(blur_vcount) // 10 bits
  );

  
  /*
    CDC (clk_pixe 74.25 Mhz -> clk_100mhz 100 MHz)
  */
  logic
   empty2;
  logic cdc_valid2;
  logic [15:0] cdc_pixel2;
  logic [10:0] cdc_hcount2;
  logic [9:0] cdc_vcount2;

  fifo cdc_fifo_2
    (.wr_clk(clk_pixel),
     .full(),
     .din({blur_hcount, blur_vcount, blur_pixel}),
     .wr_en(blur_valid),

     .rd_clk(clk_pixel),
     .empty(empty2),
     .dout({cdc_hcount2, cdc_vcount2, cdc_pixel2}),
     .rd_en(1) //always read
    );

  assign cdc_valid2 = ~empty2; //watch when empty. Ready immediately if something there



  /*
    DOWNSAMPLING 
    720 x 1280 -> 360 x 640 
  */
  logic should_pack;
  // downsample (take every other pixel from every other row)
  // only pack into spi on the valid output cycle
  assign should_pack = (cdc_hcount2[0] == 1'b0) &&
                       (cdc_vcount2[0] == 1'b0) && 
                        cdc_valid2;

  /*
    SPI CONVERSION (clk_100mhz, 100 MHz)
  */
  logic [5:0][15:0] pixels_to_send;
  always_ff @(posedge clk_100mhz) begin
    if (should_pack) begin
      pixels_to_send <= {pixels_to_send[5:0], cdc_pixel2};
    end
  end

  logic packet_ready;
  evt_counter #(
    .MAX_COUNT(6)
  ) packet_ready_counter (
    .clk_in(clk_100mhz),
    .rst_in(sys_rst),
    .evt_in(should_pack),
    .hit_max(packet_ready),
  );

  spi_send_con # (
    .DATA_WIDTH(16), // each line should send the 16 bit pixel
    .LINES(6), // six parallel lines
    .DATA_CLK_PERIOD(6), // 16.6 MHz SPI Clock
  ) spi_send (
    .clk_in(clk_100mhz),
    .rst_in(sys_rst),
    .data_in(pixels_to_send), // LINES arrays of length DATA_WIDTH bits
    .trigger_in(packet_ready),

    .chip_data_out(copi), // 6 bits (1 bit from each of the 6 pixels)
    .chip_clk_out(dclk),
    .chip_sel_out(cs)
  )
 
endmodule // top_level
 