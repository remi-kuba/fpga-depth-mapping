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
  logic [15:0] camera_pixel; //NOW 8-bit?
  logic        camera_valid;

//TODO: ADD LUMINANCE RECONSTRUCT instead
  pixel_reconstruct pixel_reconstruct_inst
  (.clk_in(clk_camera),
   .rst_in(sys_rst),
   .camera_pclk_in(cam_pclk_buf[0]),
   .camera_hs_in(cam_hsync_buf[0]),
   .camera_vs_in(cam_vsync_buf[0]),
   .camera_data_in(camera_d_buf[0]),
   .pixel_valid_out(camera_valid),
   .pixel_hcount_out(camera_hcount),
   .pixel_vcount_out(camera_vcount),
   .pixel_data_out(camera_pixel)); // the camera pixel from CAM1


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
  logic [15:0] camera_mem; //used to pass pixel data into frame buffer -- 8bit now?

  always_ff @(posedge clk_camera)begin
    // down sample  data from the camera by a factor of 2 in both
    //the x and y dimensions!
    if (sys_rst_camera) begin
      addra <= 0;
      camera_mem <= 0;  
      valid_camera_mem <= 0;
    end else begin
      addra <= camera_hcount[10:1] + (camera_vcount[9:1])*320; //x/2 + (y/2)*w
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
  logic [15:0] frame_buff_raw; //data out of frame buffer (16-bit)
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
  logic [15:0] cdc_pixel; //now 8-bit?
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
//TODO (UNFINISHED)
//CAM1 AXIS:  //potentially hold all data to write?
  logic [127:0] write_axis_tdata; //output data of stacker
  logic         write_axis_tlast;
  logic         write_axis_tready;
  logic         write_axis_tvalid;

//CAM2 AXIS:
//   logic [127:0] cam2_axis_tdata;
//   logic         cam2_axis_tlast;
//   logic         cam2_axis_tready;
//   logic         cam2_axis_tvalid;

// //SAD_OUT AXIS:
//   logic [127:0] cam2_axis_tdata;
//   logic         cam2_axis_tlast;
//   logic         cam2_axis_tready;
//   logic         cam2_axis_tvalid;

  // takes our 8-bit values and deserialize/stack them into 128-bit messages to write to DRAM
  // the data pipeline is designed such that we can fairly safe to assume its always ready.
  logic [7:0] pixel = (state == 1) ? camera_pixel : 8'b0; //TODO: UPDATE to have 3 possible inputs tdata based on state
  //potentially add different tlast
  stacker stacker_inst(
    .clk_in(clk_camera),
    .rst_in(sys_rst_camera),
    .pixel_tvalid(camera_valid),
    .pixel_tready(),
    .pixel_tdata(pixel),
    .pixel_tlast(camera_hcount == 1279 && camera_vcount == 719), // change me
    .chunk_tvalid(write_axis_tvalid),
    .chunk_tready(write_axis_tready),
    .chunk_tdata(write_axis_tdata),
    .chunk_tlast(write_axis_tlast));


//FIFO IN:
  logic [127:0] write_ui_axis_tdata;
  logic         write_ui_axis_tlast;
  logic         write_ui_axis_tready;
  logic         write_ui_axis_tvalid;
  logic         write_ui_axis_prog_empty;

  // FIFO data queue of 128-bit messages, crosses clock domains to the 81.25MHz
  // UI clock of the memory interface
  ddr_fifo_wrap write_data_fifo(
    .sender_rst(sys_rst_camera),
    .sender_clk(clk_camera),
    .sender_axis_tvalid(write_axis_tvalid),
    .sender_axis_tready(write_axis_tready),
    .sender_axis_tdata(write_axis_tdata),
    .sender_axis_tlast(write_axis_tlast),
    .receiver_clk(clk_ui),
    .receiver_axis_tvalid(write_ui_axis_tvalid),
    .receiver_axis_tready(write_ui_axis_tready),
    .receiver_axis_tdata(write_ui_axis_tdata),
    .receiver_axis_tlast(write_ui_axis_tlast),
    .receiver_axis_prog_empty(write_ui_axis_prog_empty));

  logic [127:0] read_ui_axis_tdata;
  logic         read_ui_axis_tlast;
  logic         read_ui_axis_tready;
  logic         read_ui_axis_tvalid;
  logic         read_ui_axis_prog_full;


  // The signals the MIG IP needs us to define!
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
  
  // this traffic generator handles reads and writes issued to the MIG IP,
  // which in turn handles the bus to the DDR chip.
  traffic_generator readwrite_looper(
    // Outputs
    .app_addr         (app_addr[26:0]),
    .app_cmd          (app_cmd[2:0]),
    .app_en           (app_en),
    .app_wdf_data     (app_wdf_data[127:0]),
    .app_wdf_end      (app_wdf_end),
    .app_wdf_wren     (app_wdf_wren),
    .app_wdf_mask     (app_wdf_mask[15:0]),
    .app_sr_req       (app_sr_req),
    .app_ref_req      (app_ref_req),
    .app_zq_req       (app_zq_req),
    .write_axis_ready (write_ui_axis_tready),
    .read_axis_data   (read_ui_axis_tdata),
    .read_axis_tlast  (read_ui_axis_tlast),
    .read_axis_valid  (read_ui_axis_tvalid),
    // Inputs
    .clk_in           (clk_ui),
    .rst_in           (sys_rst_ui),
    .app_rd_data      (app_rd_data[127:0]),
    .app_rd_data_end  (app_rd_data_end),
    .app_rd_data_valid(app_rd_data_valid),
    .app_rdy          (app_rdy),
    .app_wdf_rdy      (app_wdf_rdy),
    .app_sr_active    (app_sr_active),
    .app_ref_ack      (app_ref_ack),
    .app_zq_ack       (app_zq_ack),
    .init_calib_complete(init_calib_complete),
    .write_axis_data  (write_ui_axis_tdata),
    .write_axis_tlast (write_ui_axis_tlast),
    .write_axis_valid (write_ui_axis_tvalid),
    .write_axis_smallpile(write_ui_axis_prog_empty),
    .read_axis_af     (read_ui_axis_prog_full),
    .read_axis_ready  (read_ui_axis_tready) 
    .state            (tg_state)
  );

  // the MIG IP!
  ddr3_mig ddr3_mig_inst 
    (
    .ddr3_dq(ddr3_dq),
    .ddr3_dqs_n(ddr3_dqs_n),
    .ddr3_dqs_p(ddr3_dqs_p),
    .ddr3_addr(ddr3_addr),
    .ddr3_ba(ddr3_ba),
    .ddr3_ras_n(ddr3_ras_n),
    .ddr3_cas_n(ddr3_cas_n),
    .ddr3_we_n(ddr3_we_n),
    .ddr3_reset_n(ddr3_reset_n),
    .ddr3_ck_p(ddr3_ck_p),
    .ddr3_ck_n(ddr3_ck_n),
    .ddr3_cke(ddr3_cke),
    .ddr3_dm(ddr3_dm),
    .ddr3_odt(ddr3_odt),
    .sys_clk_i(clk_migref),
    .app_addr(app_addr),
    .app_cmd(app_cmd),
    .app_en(app_en),
    .app_wdf_data(app_wdf_data),
    .app_wdf_end(app_wdf_end),
    .app_wdf_wren(app_wdf_wren),
    .app_rd_data(app_rd_data),
    .app_rd_data_end(app_rd_data_end),
    .app_rd_data_valid(app_rd_data_valid),
    .app_rdy(app_rdy),
    .app_wdf_rdy(app_wdf_rdy), 
    .app_sr_req(app_sr_req),
    .app_ref_req(app_ref_req),
    .app_zq_req(app_zq_req),
    .app_sr_active(app_sr_active),
    .app_ref_ack(app_ref_ack),
    .app_zq_ack(app_zq_ack),
    .ui_clk(clk_ui), 
    .ui_clk_sync_rst(sys_rst_ui),
    .app_wdf_mask(app_wdf_mask),
    .init_calib_complete(init_calib_complete),
    .sys_rst(!sys_rst_migref) // active low
  );


  logic [127:0] read_axis_tdata;
  logic         read_axis_tlast;
  logic         read_axis_tready;
  logic         read_axis_tvalid;
  logic         read_axis_prog_empty;
  
  ddr_fifo_wrap pdfifo(
    .sender_rst(sys_rst_ui),
    .sender_clk(clk_ui),
    .sender_axis_tvalid(read_ui_axis_tvalid),
    .sender_axis_tready(read_ui_axis_tready),
    .sender_axis_tdata(read_ui_axis_tdata),
    .sender_axis_tlast(read_ui_axis_tlast),
    .sender_axis_prog_full(read_ui_axis_prog_full),
    .receiver_clk(clk_pixel),
    .receiver_axis_tvalid(read_axis_tvalid),
    .receiver_axis_tready(read_axis_tready),
    .receiver_axis_tdata(read_axis_tdata),
    .receiver_axis_tlast(read_axis_tlast),
    .receiver_axis_prog_empty(read_axis_prog_empty));

  //Display out
  logic frame_buff_tvalid;
  logic frame_buff_tready;
  logic [15:0] frame_buff_tdata;
  logic        frame_buff_tlast;

  //TODO:UPDATE OUTPUT TO CHOOSE BETWEEN SADin1, SADin2, or framebuffout
  unstacker unstacker_inst(
    .clk_in(clk_pixel),
    .rst_in(sys_rst_pixel),
    .chunk_tvalid(read_axis_tvalid),
    .chunk_tready(read_axis_tready),
    .chunk_tdata(read_axis_tdata),
    .chunk_tlast(read_axis_tlast),
    .pixel_tvalid(frame_buff_tvalid),
    .pixel_tready(frame_buff_tready),
    .pixel_tdata(output),
    .pixel_tlast(frame_buff_tlast));

//TODO: UPDATE TO HAVE 3 outputs
logic [7:0] output = (state == 3) ? frame_buff_tdata : 8'b0;

  // TODO: assign frame_buff_tready
  // I did this in 1 (kind of long) line. an always_comb block could also work.
  assign frame_buff_tready = active_draw_hdmi && (~frame_buff_tlast || (hcount_hdmi == 1279 && vcount_hdmi == 719)); // change me!!
  
  assign frame_buff_dram = frame_buff_tvalid ? frame_buff_tdata : 16'h2277;



  /*
    LINE BUFFER (clk_pixel, 74.25 MHz) + 
    ANTI-ALIASING GAUSSIAN BLUR (clk_pixel, 74.25 MHz)
  */

  logic [10:0] blur_hcount;  //hcount from blur module
  logic [9:0] blur_vcount; //vcount from blur module
  logic [15:0] blur_pixel; //pixel data from blur module //NOW 8-bit?
  logic blur_valid; //valid signals for blur module
  //full resolution filter
  blur_filter #(.HRES(1280),.VRES(720))
    blur(
    .clk_in(clk_pixel), 
    .rst_in(sys_rst_pixel),
    .data_valid_in(cdc_valid),
    .pixel_data_in(cdc_pixel), // 16 bits -- now 8?
    .hcount_in(cdc_hcount), // 11 bits
    .vcount_in(cdc_vcount), // 10 bits
    .data_valid_out(blur_valid), 
    .pixel_data_out(blur_pixel), // 16 bits -- now 8?
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
  logic [5:0][7:0] pixels_to_send;
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
    .DATA_WIDTH(8), // each line should send the 16 bit pixel
    .LINES(4), // six parallel lines
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
 