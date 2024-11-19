`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module top_level(
  input wire clk_100mhz, //100 MHz onboard clock
  input wire [15:0] sw, //all 16 input slide switches
  input wire [3:0] btn, //all four momentary button switches

  // HDMI
  output logic [2:0] hdmi_tx_p, //hdmi output signals (positives) (blue, green, red)
  output logic [2:0] hdmi_tx_n, //hdmi output signals (negatives) (blue, green, red)
  output logic hdmi_clk_p, hdmi_clk_n //differential hdmi clock

  // SPI 
  output logic dclk, // data clock output of SPI controller
  output logic [5:0] cipo, // six parallel data outputs of SPI controller
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
  // this port also is specifically set to high drive by the XDC file.
  // Camera clock only runs when holding btn[1] down (protect cameras)
  assign cam_xclk = btn[1] ? clk_xc : 1'b0;;

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
  
  // video signal generator signals
  logic          hsync_hdmi;
  logic          vsync_hdmi;
  logic [10:0]  hcount_hdmi;
  logic [9:0]    vcount_hdmi;
  logic          active_draw_hdmi;
  logic          new_frame_hdmi;
  logic [5:0]    frame_count_hdmi;
  logic          nf_hdmi;
  // rgb output values
  logic [7:0]          red,green,blue;


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
   .rst_in(sys_rst),
   .camera_pclk_in(cam_pclk_buf[0]),
   .camera_hs_in(cam_hsync_buf[0]),
   .camera_vs_in(cam_vsync_buf[0]),
   .camera_data_in(camera_d_buf[0]),
   .pixel_valid_out(camera_valid),
   .pixel_hcount_out(camera_hcount),
   .pixel_vcount_out(camera_vcount),
   .pixel_data_out(camera_pixel));


  //two-port BRAM used to hold output image from DRAM.
  //we're going to down-sample by a factor of 2 in both dimensions
  //so we have 640 by 360.  
  //even if we could line it up once, the clocks of both systems will drift over time
  //so to avoid this sync issue, we use a conflict-resolution device...the frame buffer
  //instead we use a frame buffer as a go-between. The DRAM --> FIFO sends pixels in at
  //its own rate, and we pull them out for display at the 720p rate/requirement
  //this avoids the whole sync issue. 
  localparam FB_DEPTH = 640*360;
  localparam FB_SIZE = $clog2(FB_DEPTH);
  logic [FB_SIZE-1:0] addra; //used to specify address to write to in frame buffer

  //Only for directly using camera data
  logic valid_camera_mem; //used to enable writing pixel data to frame buffer
  logic [15:0] camera_mem; //used to pass pixel data into frame buffer

  always_ff @(posedge clk_camera)begin
    // down sample  data from the camera by a factor of 2 in both
    //the x and y dimensions! TO DO
    if (sys_rst_camera) begin
      addra <= 0;
      camera_mem <= 0;  
      valid_camera_mem <= 0;
    end else begin
      addra <= camera_hcount[10:2] + (camera_vcount[9:2])*320; //x/4 + (y/4)*w
      camera_mem <= camera_pixel;
      if (camera_hcount[0] == 0 && camera_vcount[0] == 0 && camera_valid) begin //if both hcount and vcount are divisible by 2
        valid_camera_mem <= 1;
      end else begin
        valid_camera_mem <= 0;
      end
    end
  end

  //frame buffer from IP
  blk_mem_gen_0 frame_buffer (
    .addra(addra), //pixels are stored using this math
    .clka(clk_camera),
    .wea(valid_camera_mem),
    .dina(camera_mem),
    .ena(1'b1),
    .douta(), //never read from this side
    .addrb(addrb),//transformed lookup pixel
    .dinb(16'b0),
    .clkb(clk_pixel),
    .web(1'b0),
    .enb(1'b1),
    .doutb(frame_buff_raw)
  );
  logic [15:0] frame_buff_raw; //data out of frame buffer (565)
  logic [FB_SIZE-1:0] addrb; //used to lookup address in memory for reading from buffer
  logic good_addrb; //used to indicate within valid frame for scaling


  // Scale pixel coordinates from HDMI to the frame buffer to grab the right pixel
  //scaling logic -- 2X
  always_ff @(posedge clk_pixel)begin
    //2X scaling from frame buffer
    addrb <= (hcount_hdmi>>1) + 320*(vcount_hdmi>>1); //Shift to divide by 2
    good_addrb <=(hcount_hdmi<640)&&(vcount_hdmi<360);
  end

  //split fame_buff into 3 8 bit Y luminance channels
  //remapped frame_buffer outputs with 8 bits for r, g, b
  logic [7:0] fb_red, fb_green, fb_blue;
  always_ff @(posedge clk_pixel)begin
    fb_red <= good_addrb ? frame_buff_raw[7:0] : 8'b0;
    fb_green <= good_addrb ? frame_buff_raw[7:0] : 8'b0;
    fb_blue <= good_addrb ? frame_buff_raw[7:0] : 8'b0;
  end


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


/* SECTION FOR ALL DRAM (6 FIFOs -- 3 pairs for camera 1 data, camera 2 data, and SAD module input/output)*/
//CAM1 AXIS:
  logic [127:0] cam1_axis_tdata;
  logic         cam1_axis_tlast;
  logic         cam1_axis_tready;
  logic         cam1_axis_tvalid;

//CAM1 FIFO OUT:
  logic [127:0] cam1_ui_axis_tdata;
  logic         cam1_ui_axis_tlast;
  logic         cam1_ui_axis_tready;
  logic         cam1_ui_axis_tvalid;
  logic         cam1_ui_axis_prog_empty;

//CAM2 AXIS:
  logic [127:0] cam2_axis_tdata;
  logic         cam2_axis_tlast;
  logic         cam2_axis_tready;
  logic         cam2_axis_tvalid;

//CAM2 FIFO OUT:
  logic [127:0] cam2_ui_axis_tdata;
  logic         cam2_ui_axis_tlast;
  logic         cam2_ui_axis_tready;
  logic         cam2_ui_axis_tvalid;
  logic         cam2_ui_axis_prog_empty;

//MIG IP (required):
  // these are the signals that the MIG IP needs for us to define!
  // MIG UI --> generic outputs
  logic [26:0]  app_addr;
  logic [2:0]   app_cmd;
  logic         app_en;
  // MIG UI --> write outputs
  logic [127:0] app_wdf_data;
  logic         app_wdf_end;
  logic         app_wdf_wren;
  logic [15:0]  app_wdf_mask;
  // MIG UI --> read inputs
  logic [127:0] app_rd_data;
  logic         app_rd_data_end;
  logic         app_rd_data_valid;
  // MIG UI --> generic inputs
  logic         app_rdy;
  logic         app_wdf_rdy;
  // MIG UI --> misc
  logic         app_sr_req; 
  logic         app_ref_req;
  logic         app_zq_req; 
  logic         app_sr_active;
  logic         app_ref_ack;
  logic         app_zq_ack;
  logic         init_calib_complete;

//READ CAM 1:
  logic [127:0] read1_ui_axis_tdata;
  logic         read1_ui_axis_tlast;
  logic         read1_ui_axis_tready;
  logic         read1_ui_axis_tvalid;
  logic         read1_ui_axis_prog_full;

//READ CAM 1 AXIS:
  logic [127:0] read1_axis_tdata;
  logic         read1_axis_tlast;
  logic         read1_axis_tready;
  logic         read1_axis_tvalid;
  logic         read1_axis_prog_empty;

//READ CAM 2:
  logic [127:0] read2_ui_axis_tdata;
  logic         read2_ui_axis_tlast;
  logic         read2_ui_axis_tready;
  logic         read2_ui_axis_tvalid;
  logic         read2_ui_axis_prog_full;

//READ CAM 2 AXIS:
  logic [127:0] read2_axis_tdata;
  logic         read2_axis_tlast;
  logic         read2_axis_tready;
  logic         read2_axis_tvalid;
  logic         read2_axis_prog_empty;



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




  // HDMI video signal generator
   video_sig_gen vsg
     (
      .pixel_clk_in(clk_pixel),
      .rst_in(sys_rst_pixel),
      .hcount_out(hcount_hdmi),
      .vcount_out(vcount_hdmi),
      .vs_out(vsync_hdmi),
      .hs_out(hsync_hdmi),
      .nf_out(nf_hdmi),
      .ad_out(active_draw_hdmi),
      .fc_out(frame_count_hdmi)
      );


   tmds_encoder tmds_red(
       .clk_in(clk_pixel),
       .rst_in(sys_rst_pixel),
       .data_in(red),
       .control_in(2'b0),
       .ve_in(active_draw_hdmi),
       .tmds_out(tmds_10b[2]));

   tmds_encoder tmds_green(
         .clk_in(clk_pixel),
         .rst_in(sys_rst_pixel),
         .data_in(green),
         .control_in(2'b0),
         .ve_in(active_draw_hdmi),
         .tmds_out(tmds_10b[1]));

   tmds_encoder tmds_blue(
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .data_in(blue),
        .control_in({vsync_hdmi,hsync_hdmi}),
        .ve_in(active_draw_hdmi),
        .tmds_out(tmds_10b[0]));

   tmds_serializer red_ser(
         .clk_pixel_in(clk_pixel),
         .clk_5x_in(clk_5x),
         .rst_in(sys_rst_pixel),
         .tmds_in(tmds_10b[2]),
         .tmds_out(tmds_signal[2]));
   tmds_serializer green_ser(
         .clk_pixel_in(clk_pixel),
         .clk_5x_in(clk_5x),
         .rst_in(sys_rst_pixel),
         .tmds_in(tmds_10b[1]),
         .tmds_out(tmds_signal[1]));
   tmds_serializer blue_ser(
         .clk_pixel_in(clk_pixel),
         .clk_5x_in(clk_5x),
         .rst_in(sys_rst_pixel),
         .tmds_in(tmds_10b[0]),
         .tmds_out(tmds_signal[0]));

   OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
   OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
   OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
   OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));

 
endmodule // top_level
 