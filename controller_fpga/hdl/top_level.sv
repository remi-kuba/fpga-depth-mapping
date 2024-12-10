`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module top_level(
  input wire clk_100mhz, //100 MHz onboard clock
 output logic [15:0] led,
  // seven segment
  output logic [3:0]  ss0_an,//anode control for upper four digits of seven-seg display
  output logic [3:0]  ss1_an,//anode control for lower four digits of seven-seg display
  output logic [6:0]  ss0_c, //cathode controls for the segments of upper four digits
  output logic [6:0]  ss1_c, //cathod controls for the segments of lower four digits
  // HDMI
  output logic [2:0] hdmi_tx_p, //hdmi output signals (positives) (blue, green, red)
  output logic [2:0] hdmi_tx_n, //hdmi output signals (negatives) (blue, green, red)
  output logic hdmi_clk_p, hdmi_clk_n, //differential hdmi clock
  // camera bus
  input wire [7:0]    camera_d, // 8 parallel data wires
  output logic        cam_xclk, // XC driving camera
  input wire          cam_hsync, // camera hsync wire
  input wire          cam_vsync, // camera vsync wire
  input wire          cam_pclk, // camera pixel clock
  inout wire          i2c_scl, // i2c inout clock
  inout wire          i2c_sda, // i2c inout data
  input wire [15:0]   sw,
  input wire [3:0]    btn,
  output logic [2:0]  rgb0,
  output logic [2:0]  rgb1,

  // DDR3 ports -- Causes Multiple Driver Nets if uncommented, but other undefined error
  inout wire [15:0]  ddr3_dq,
  inout wire [1:0]   ddr3_dqs_n,
  inout wire [1:0]   ddr3_dqs_p,
  output wire [12:0] ddr3_addr,
  output wire [2:0]  ddr3_ba,
  output wire        ddr3_ras_n,
  output wire        ddr3_cas_n,
  output wire        ddr3_we_n,
  output wire        ddr3_reset_n,
  output wire        ddr3_ck_p,
  output wire        ddr3_ck_n,
  output wire        ddr3_cke,
  output wire [1:0]  ddr3_dm,
  output wire        ddr3_odt
  );

  // TODO: Change stacker to accomodate an early pixel_tlast
  // in which case count is set to 0 and valid_out and ready_in are set HI
  /*
    RESETS
  */
  // btn[0] controls system reset
  logic sys_rst_camera;
  logic sys_rst_pixel;
  logic sys_rst;
  assign sys_rst_camera = btn[0];
  assign sys_rst_pixel = sys_rst_camera;
  assign sys_rst = sys_rst_camera;
  // this port also is specifically set to high drive by the XDC file.
  // Camera clock only runs when holding btn[1] down (protect cameras)
  // assign cam_xclk = btn[1] ? clk_xc : 1'b0;

  /*
    CLOCKS
  */

  logic clk_camera; // 200 MHz
  logic clk_pixel; // 74.25 MHz
  // Middle clocks
  logic clk_100_passthrough;
  logic clk_5x;
  logic clk_xc;
  //MIG clocks
  logic          clk_migref;
  logic          sys_rst_migref;
  logic          clk_ui;
  logic          sys_rst_ui;
  
  cw_fast_clk_wiz wizard_migcam
    (.clk_in1(clk_100mhz),
     .clk_camera(clk_camera),
     .clk_mig(clk_migref),
     .clk_xc(clk_xc),
     .clk_100(clk_100_passthrough),
     .locked(1'b0),
     .reset(0));

  cw_hdmi_clk_wiz wizard_hdmi
    (.sysclk(clk_100_passthrough),
     .clk_pixel(clk_pixel),
     .clk_tmds(clk_5x),
     .reset(0));

  // assign camera's xclk to pmod port: drive the operating clock of the camera!
  // this port also is specifically set to high drive by the XDC file.
     assign cam_xclk = clk_xc;

     assign sys_rst_camera = btn[0]; //use for resetting camera side of logic
     assign sys_rst_pixel = btn[0]; //use for resetting hdmi/draw side of logic
     assign sys_rst_migref = btn[0];
     
  // video signal generator signals
  logic          hsync_hdmi;
  logic          vsync_hdmi;
  logic [10:0]   hcount_hdmi;
  logic [9:0]    vcount_hdmi;
  logic          active_draw_hdmi;
  logic          new_frame_hdmi;
  logic [5:0]    frame_count_hdmi;
  logic          nf_hdmi;

  // rgb output values
  logic [7:0]    red,green,blue;

  /*
    CAMERA 
                  ** Handling input from the camera **
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

  logic [31:0] val_to_display;
  logic [6:0] ss_c;
  assign ss0_c = ss_c;
  assign ss1_c = ss_c;
  seven_segment_controller mssc(.clk_in(clk_100_passthrough),
                               .rst_in(sys_rst_camera),
                               .val_in(val_to_display),
                               .cat_out(ss_c),
                               .an_out({ss0_an, ss1_an}));

  assign val_to_display = 32'd7;

  /*
    LUMINANCE RECONSTRUCT (clk_camera, 200 MHz)
  */
  logic [10:0] camera_hcount;
  logic [9:0]  camera_vcount;
  logic [7:0]  camera_pixel; // 8-bit
  logic        camera_valid;

luminance_reconstruct #(
    .HCOUNT_WIDTH(10),
    .VCOUNT_WIDTH(9)
  ) lr (
    .clk_in(clk_camera),
    .rst_in(sys_rst_camera),
    .camera_pclk_in(cam_pclk_buf[0]),
    .camera_hs_in(cam_hsync_buf[0]),
    .camera_vs_in(cam_vsync_buf[0]),
    .camera_data_in(camera_d_buf[0]),
    .pixel_valid_out(camera_valid),
    .pixel_hcount_out(camera_hcount),
    .pixel_vcount_out(camera_vcount),
    .pixel_data_out(camera_pixel)// the camera pixel from CAM1
  );



  // // ROM holding pre-built camera settings to send
  // xilinx_single_port_ram_read_first
  //   #(
  //   .RAM_WIDTH(24),
  //   .RAM_DEPTH(256),
  //   .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
  //   .INIT_FILE("rom_640_360.mem")
  // ) registers
  //     (
  //   .addra(bram_addr),     // Address bus, width determined from RAM_DEPTH
  //   .dina(24'b0),          // RAM input data, width determined from RAM_WIDTH
  //   .clka(clk_camera),     // Clock
  //   .wea(1'b0),            // Write enable
  //   .ena(1'b1),            // RAM Enable, for additional power savings, disable port when not in use
  //   .rsta(sys_rst_camera), // Output reset (does not affect memory contents)
  //   .regcea(1'b1),         // Output register enable
  //   .douta(bram_dout)      // RAM output data, width determined from RAM_WIDTH
  // );
  /*
    CDC (clk_camera 200 Mhz -> clk_100mhz 100 MHz)
  */
  logic empty;
  logic cdc_valid1;
  logic [15:0] cdc_pixel1; //now 8-bit?
  logic [10:0] cdc_hcount1;
  logic [9:0] cdc_vcount1;

  fifo cdc_fifo_camera
    (.wr_clk(clk_camera),
     .full(),
     .din({camera_hcount, camera_vcount, camera_pixel}),
     .wr_en(camera_valid),

     .rd_clk(clk_100_passthrough),
     .empty(empty),
     .dout({cdc_hcount1, cdc_vcount1, cdc_pixel1}),
     .rd_en(1) //always read
    );

  assign cdc_valid1 = ~empty; //watch when empty. Ready immediately if something there


/* SECTION FOR ALL DRAM (6 FIFOs -- 3 pairs for camera 1 data, camera 2 data, and SAD module input/output)*/

//CAM1 AXIS:  //potentially hold all data to write?
  logic [127:0] wr_cam1_axis_tdata; //output data of stacker
  logic         wr_cam1_axis_tlast;
  logic         wr_cam1_axis_tready;
  logic         wr_cam1_axis_tvalid;

//CAM2 AXIS:
  logic [127:0] wr_cam2_axis_tdata;
  logic         wr_cam2_axis_tlast;
  logic         wr_cam2_axis_tready;
  logic         wr_cam2_axis_tvalid;

// //SAD_OUT AXIS:
  logic [127:0] wr_sad_axis_tdata;
  logic         wr_sad_axis_tlast;
  logic         wr_sad_axis_tready;
  logic         wr_sad_axis_tvalid;

  // takes our 8-bit values and deserialize/stack them into 128-bit messages to write to DRAM
  // the data pipeline is designed such that we can fairly safe to assume its always ready.

  //potentially add different tlast
  stacker cam1_stacker(
    .clk_in(clk_camera),
    .rst_in(sys_rst),
    .pixel_tvalid(camera_valid),
    .pixel_tready(),
    .pixel_tdata(camera_pixel),
    .pixel_tlast(camera_hcount == 639 && camera_vcount == 359), // change me
    .chunk_tvalid(wr_cam1_axis_tvalid),
    .chunk_tready(wr_cam1_axis_tready),
    .chunk_tdata(wr_cam1_axis_tdata),
    .chunk_tlast(wr_cam1_axis_tlast));

//TODO: GET DATA/PIXELS FROM SPI
//FOR NOW JUST TAKING A COPY FROM THE CAMERA
  stacker cam2_stacker(
    .clk_in(clk_camera),
    .rst_in(sys_rst),
    .pixel_tvalid(camera_valid),
    .pixel_tready(),
//////
    .pixel_tdata(camera_pixel), //reconstructed pixel
    .pixel_tlast(camera_hcount == 639 && camera_vcount == 359), // final pixel
//////
    .chunk_tvalid(wr_cam2_axis_tvalid),
    .chunk_tready(wr_cam2_axis_tready),
    .chunk_tdata(wr_cam2_axis_tdata),
    .chunk_tlast(wr_cam2_axis_tlast));

//OUTPUT OF SAD from depth_mapper
  stacker sad_stacker(
    .clk_in(clk_100_passthrough),
    .rst_in(sys_rst),
    .pixel_tvalid(sad_valid_out),
    .pixel_tready(),
    .pixel_tdata(sad_data_out),//calculated pixel
    .pixel_tlast(sad_tlast), // final pixel
    .chunk_tvalid(wr_sad_axis_tvalid),
    .chunk_tready(wr_sad_axis_tready),
    .chunk_tdata(wr_sad_axis_tdata),
    .chunk_tlast(wr_sad_axis_tlast));


// CAM1 FIFO IN:
  logic [127:0] wr_cam1_ui_axis_tdata;
  logic         wr_cam1_ui_axis_tlast;
  logic         wr_cam1_ui_axis_tready;
  logic         wr_cam1_ui_axis_tvalid;
  logic         wr_cam1_ui_axis_prog_empty;
// CAM2 FIFO IN:
  logic [127:0] wr_cam2_ui_axis_tdata;
  logic         wr_cam2_ui_axis_tlast;
  logic         wr_cam2_ui_axis_tready;
  logic         wr_cam2_ui_axis_tvalid;
  logic         wr_cam2_ui_axis_prog_empty;
// SAD FIFO IN:
  logic [127:0] wr_sad_ui_axis_tdata;
  logic         wr_sad_ui_axis_tlast;
  logic         wr_sad_ui_axis_tready;
  logic         wr_sad_ui_axis_tvalid;
  logic         wr_sad_ui_axis_prog_empty;


  // 3 x FIFO [in] data queues of 128-bit messages, crosses clock domains to the 81.25MHz
  // UI clock of the memory interface

  //CAM1 FIFO
  ddr_fifo_wrap wr_cam1_data_fifo(
    .sender_rst(sys_rst),
    .sender_clk(clk_camera),
    .sender_axis_tvalid(wr_cam1_axis_tvalid),
    .sender_axis_tready(wr_cam1_axis_tready),
    .sender_axis_tdata(wr_cam1_axis_tdata),
    .sender_axis_tlast(wr_cam1_axis_tlast),
    .receiver_clk(clk_ui),
    .receiver_axis_tvalid(wr_cam1_ui_axis_tvalid),
    .receiver_axis_tready(wr_cam1_ui_axis_tready),
    .receiver_axis_tdata(wr_cam1_ui_axis_tdata),
    .receiver_axis_tlast(wr_cam1_ui_axis_tlast),
    .receiver_axis_prog_empty(wr_cam1_ui_axis_prog_empty));

  //CAM2 FIFO
  ddr_fifo_wrap wr_cam2_data_fifo(
    .sender_rst(sys_rst),
    .sender_clk(clk_camera),
    .sender_axis_tvalid(wr_cam2_axis_tvalid),
    .sender_axis_tready(wr_cam2_axis_tready),
    .sender_axis_tdata(wr_cam2_axis_tdata),
    .sender_axis_tlast(wr_cam2_axis_tlast),
    .receiver_clk(clk_ui),
    .receiver_axis_tvalid(wr_cam2_ui_axis_tvalid),
    .receiver_axis_tready(wr_cam2_ui_axis_tready),
    .receiver_axis_tdata(wr_cam2_ui_axis_tdata),
    .receiver_axis_tlast(wr_cam2_ui_axis_tlast),
    .receiver_axis_prog_empty(wr_cam2_ui_axis_prog_empty));

  //SAD FIFO
  ddr_fifo_wrap sad_data_fifo(
    .sender_rst(sys_rst),
    .sender_clk(clk_100_passthrough),
    .sender_axis_tvalid(wr_sad_axis_tvalid),
    .sender_axis_tready(wr_sad_axis_tready),
    .sender_axis_tdata(wr_sad_axis_tdata),
    .sender_axis_tlast(wr_sad_axis_tlast),
    .receiver_clk(clk_ui),
    .receiver_axis_tvalid(wr_sad_ui_axis_tvalid),
    .receiver_axis_tready(wr_sad_ui_axis_tready),
    .receiver_axis_tdata(wr_sad_ui_axis_tdata),
    .receiver_axis_tlast(wr_sad_ui_axis_tlast),
    .receiver_axis_prog_empty(wr_sad_ui_axis_prog_empty));

  //CAM1 UI AXIS
  logic [127:0] r_cam1_ui_axis_tdata;
  logic         r_cam1_ui_axis_tlast;
  logic         r_cam1_ui_axis_tready;
  logic         r_cam1_ui_axis_tvalid;
  logic         r_cam1_ui_axis_prog_full;

  //CAM2 UI AXIS
  logic [127:0] r_cam2_ui_axis_tdata;
  logic         r_cam2_ui_axis_tlast;
  logic         r_cam2_ui_axis_tready;
  logic         r_cam2_ui_axis_tvalid;
  logic         r_cam2_ui_axis_prog_full;

  //HDMI UI AXIS
  logic [127:0] r_hdmi_ui_axis_tdata;
  logic         r_hdmi_ui_axis_tlast;
  logic         r_hdmi_ui_axis_tready;
  logic         r_hdmi_ui_axis_tvalid;
  logic         r_hdmi_ui_axis_prog_full;

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
    .wr_cam1_axis_ready (wr_cam1_ui_axis_tready),
    .wr_cam2_axis_ready (wr_cam2_ui_axis_tready),
    .wr_sad_axis_ready (wr_sad_ui_axis_tready),

    .r_cam1_axis_data   (r_cam1_ui_axis_tdata),
    .r_cam1_axis_tlast  (r_cam1_ui_axis_tlast),
    .r_cam1_axis_valid  (r_cam1_ui_axis_tvalid),
    .r_cam2_axis_data   (r_cam2_ui_axis_tdata),
    .r_cam2_axis_tlast  (r_cam2_ui_axis_tlast),
    .r_cam2_axis_valid  (r_cam2_ui_axis_tvalid),
    .r_hdmi_axis_data   (r_hdmi_ui_axis_tdata),
    .r_hdmi_axis_tlast  (r_hdmi_ui_axis_tlast),
    .r_hdmi_axis_valid  (r_hdmi_ui_axis_tvalid),
    
    // Inputs
    .clk_in           (clk_ui),
    .rst_in           (sys_rst),
    .app_rd_data      (app_rd_data[127:0]),
    .app_rd_data_end  (app_rd_data_end),
    .app_rd_data_valid(app_rd_data_valid),
    .app_rdy          (app_rdy),
    .app_wdf_rdy      (app_wdf_rdy),
    .app_sr_active    (app_sr_active),
    .app_ref_ack      (app_ref_ack),
    .app_zq_ack       (app_zq_ack),
    .init_calib_complete(init_calib_complete),

    .wr_cam1_axis_data  (wr_cam1_ui_axis_tdata),
    .wr_cam1_axis_tlast (wr_cam1_ui_axis_tlast),
    .wr_cam1_axis_valid (wr_cam1_ui_axis_tvalid),
    .wr_cam1_axis_smallpile(wr_cam1_ui_axis_prog_empty),
    .wr_cam2_axis_data  (wr_cam2_ui_axis_tdata),
    .wr_cam2_axis_tlast (wr_cam2_ui_axis_tlast),
    .wr_cam2_axis_valid (wr_cam2_ui_axis_tvalid),
    .wr_cam2_axis_smallpile(wr_cam2_ui_axis_prog_empty),
    .wr_sad_axis_data  (wr_sad_ui_axis_tdata),
    .wr_sad_axis_tlast (wr_sad_ui_axis_tlast),
    .wr_sad_axis_valid (wr_sad_ui_axis_tvalid),
    .wr_sad_axis_smallpile(wr_sad_ui_axis_prog_empty),

    .r_cam1_axis_af     (r_cam1_ui_axis_prog_full),
    .r_cam1_axis_ready  (r_cam1_ui_axis_tready),
    .r_cam2_axis_af     (r_cam2_ui_axis_prog_full),
    .r_cam2_axis_ready  (r_cam2_ui_axis_tready), 
    .r_hdmi_axis_af     (r_hdmi_ui_axis_prog_full),
    .r_hdmi_axis_ready  (r_hdmi_ui_axis_tready) 
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
    // .device_temp(device_temp),
    .sys_rst(!sys_rst_migref) // active low
  );

  //CAM1 AXIS
  logic [127:0] r_cam1_axis_tdata;
  logic         r_cam1_axis_tlast;
  logic         r_cam1_axis_tready;
  logic         r_cam1_axis_tvalid;
  logic         r_cam1_axis_prog_empty;
  //CAM2 AXIS
  logic [127:0] r_cam2_axis_tdata;
  logic         r_cam2_axis_tlast;
  logic         r_cam2_axis_tready;
  logic         r_cam2_axis_tvalid;
  logic         r_cam2_axis_prog_empty;
  //HDMI (output) AXIS
  logic [127:0] r_hdmi_axis_tdata;
  logic         r_hdmi_axis_tlast;
  logic         r_hdmi_axis_tready;
  logic         r_hdmi_axis_tvalid;
  logic         r_hdmi_axis_prog_empty;
  
  // 3 x FIFO [out] data queues of 128-bit messages, crosses clock domains to the 81.25MHz

  //CAM1 OUT FIFO
  ddr_fifo_wrap rd_cam1_fifo(
    .sender_rst(sys_rst),
    .sender_clk(clk_ui),
    .sender_axis_tvalid(r_cam1_ui_axis_tvalid),
    .sender_axis_tready(r_cam1_ui_axis_tready),
    .sender_axis_tdata(r_cam1_ui_axis_tdata),
    .sender_axis_tlast(r_cam1_ui_axis_tlast),
    .sender_axis_prog_full(r_cam1_ui_axis_prog_full),
    .receiver_clk(clk_100_passthrough),
    .receiver_axis_tvalid(r_cam1_axis_tvalid),
    .receiver_axis_tready(r_cam1_axis_tready),
    .receiver_axis_tdata(r_cam1_axis_tdata),
    .receiver_axis_tlast(r_cam1_axis_tlast),
    .receiver_axis_prog_empty(r_cam1_axis_prog_empty));

  //CAM2 OUT FIFO
  ddr_fifo_wrap rd_cam2_fifo(
    .sender_rst(sys_rst),
    .sender_clk(clk_ui),
    .sender_axis_tvalid(r_cam2_ui_axis_tvalid),
    .sender_axis_tready(r_cam2_ui_axis_tready),
    .sender_axis_tdata(r_cam2_ui_axis_tdata),
    .sender_axis_tlast(r_cam2_ui_axis_tlast),
    .sender_axis_prog_full(r_cam2_ui_axis_prog_full),
    .receiver_clk(clk_100_passthrough),
    .receiver_axis_tvalid(r_cam2_axis_tvalid),
    .receiver_axis_tready(r_cam2_axis_tready),
    .receiver_axis_tdata(r_cam2_axis_tdata),
    .receiver_axis_tlast(r_cam2_axis_tlast),
    .receiver_axis_prog_empty(r_cam2_axis_prog_empty));

  //HDMI OUT FIFO
  ddr_fifo_wrap rd_hdmi_fifo(
    .sender_rst(sys_rst),
    .sender_clk(clk_ui),
    .sender_axis_tvalid(r_hdmi_ui_axis_tvalid),
    .sender_axis_tready(r_hdmi_ui_axis_tready),
    .sender_axis_tdata(r_hdmi_ui_axis_tdata),
    .sender_axis_tlast(r_hdmi_ui_axis_tlast),
    .sender_axis_prog_full(r_hdmi_ui_axis_prog_full),
    .receiver_clk(clk_pixel),
    .receiver_axis_tvalid(r_hdmi_axis_tvalid),
    .receiver_axis_tready(r_hdmi_axis_tready),
    .receiver_axis_tdata(r_hdmi_axis_tdata),
    .receiver_axis_tlast(r_hdmi_axis_tlast),
    .receiver_axis_prog_empty(r_hdmi_axis_prog_empty));

  //Display out
  logic         y_pix_tvalid;
  logic         y_pix_tready;
  logic [7:0]   y_pix_tdata;
  logic         y_pix_tlast;
  //Camera 1 out
  logic         stored_cam1_tvalid;
  logic [7:0]   stored_cam1_tdata;
  logic         stored_cam1_tlast;
  //Camera 2 out
  logic         stored_cam2_tvalid;
  logic [7:0]   stored_cam2_tdata;
  logic         stored_cam2_tlast;

  logic         sad_input_tready; //share tready for both camera outputs
  
  //SAD input 1 from CAM1
  unstacker r_cam1_unstacker(
    .clk_in(clk_100_passthrough),
    .rst_in(sys_rst),
    .chunk_tvalid(r_cam1_axis_tvalid),
    .chunk_tready(r_cam1_axis_tready),
    .chunk_tdata(r_cam1_axis_tdata),
    .chunk_tlast(r_cam1_axis_tlast),
    .pixel_tvalid(stored_cam1_tvalid),
    .pixel_tready(sad_input_tready),
    .pixel_tdata(stored_cam1_tdata),
    .pixel_tlast(stored_cam1_tlast));

//SAD input 2 from CAM2
  unstacker r_cam2_unstacker(
    .clk_in(clk_100_passthrough),
    .rst_in(sys_rst),
    .chunk_tvalid(r_cam2_axis_tvalid),
    .chunk_tready(r_cam2_axis_tready),
    .chunk_tdata(r_cam2_axis_tdata),
    .chunk_tlast(r_cam2_axis_tlast),
    .pixel_tvalid(stored_cam2_tvalid),
    .pixel_tready(sad_input_tready),
    .pixel_tdata(stored_cam2_tdata),
    .pixel_tlast(stored_cam2_tlast));

//HDMI fram_buff reader
  unstacker r_hdmi_unstacker(
    .clk_in(clk_pixel),
    .rst_in(sys_rst),
    .chunk_tvalid(r_hdmi_axis_tvalid),
    .chunk_tready(r_hdmi_axis_tready),
    .chunk_tdata(r_hdmi_axis_tdata),
    .chunk_tlast(r_hdmi_axis_tlast),
    .pixel_tvalid(y_pix_tvalid),
    .pixel_tready(y_pix_tready),
    .pixel_tdata(y_pix_tdata),
    .pixel_tlast(y_pix_tlast));


  //assign y_pix_tready
  assign y_pix_tready = active_draw_hdmi && (~y_pix_tlast || (hcount_hdmi == 639 && vcount_hdmi == 359));
  
  //assign sad_input_tready
  assign sad_input_tready = stored_cam1_tvalid && stored_cam2_tvalid;
  
  logic end_of_row;
  logic end_of_column;

  evt_counter #(.MAX_COUNT(640)) hcounter1
  ( .clk_in(clk_100_passthrough),
    .rst_in(sys_rst),
    .evt_in(sad_input_tready),
    .count_out(hcount_sad_in),
    .hit_max(end_of_row)
  );
  evt_counter #(.MAX_COUNT(360)) vcounter1
  ( .clk_in(clk_100_passthrough),
    .rst_in(sys_rst),
    .evt_in(end_of_row),
    .count_out(vcount_sad_in),
    .hit_max(end_of_column) // could be used for a new frame
  );

  logic [10:0]  hcount_sad_in;
  logic [9:0]   vcount_sad_in;

  logic         sad_valid_out;
  logic [7:0]   sad_data_out;
  logic         sad_tlast;

  logic [10:0]  hcount_sad_out;
  logic [9:0]   vcount_sad_out;

depth_mapper sad_calculator(
  .clk_in(clk_100_passthrough), //100 MHz
  .rst_in(sys_rst),
  //Inputs from cam1 and cam2 data
  .data_cam1_valid(sad_input_tready), //same handshake for both (ready depends on tvalid)
  .data_cam2_valid(sad_input_tready),
  .cam1_pixel_data(stored_cam1_tdata),
  .cam2_pixel_data(stored_cam2_tdata),
  .hcount_in(hcount_sad_in),
  .vcount_in(vcount_sad_in),
  //Outputs
  .data_valid_out(sad_valid_out),
  .pixel_depth_out(sad_data_out),
  .hcount_out(hcount_sad_out),
  .vcount_out(vcount_sad_out)
  );

  assign sad_tlast = (hcount_sad_out == 639) && (vcount_sad_out == 359);

  
  /*
    CDC (clk_100mhz 100 MHz -> clk_pixel 74.25 Mhz)
  */
  // logic         empty2;
  // logic         cdc_valid2;
  // logic [7:0]   cdc_pixel2;
  // logic [10:0]  cdc_hcount2;
  // logic [9:0]   cdc_vcount2;
  // logic [7:0]   y_pixel;

  // logic         empty2;
  // logic         cdc_valid2;
  // logic [7:0]   cdc_pixel2;
  // logic [10:0]  cdc_hcount2;
  // logic [9:0]   cdc_vcount2;
  // logic [7:0]   y_pixel;

  

  // fifo cdc_fifo_hdmi
  //   (.wr_clk(clk_100_passthrough),
  //    .full(),
  //    .din(y_pix_tdata),
  //    .wr_en(y_pix_tvalid),

  //    .rd_clk(clk_pixel),
  //    .empty(empty2),
  //    .dout(y_pixel),
  //    .rd_en(1) //always read
  //   );
  
  // assign cdc_valid2 = ~empty2; //watch when empty. Ready immediately if something there

  // logic [(640*360-1):0] addra;
  // logic [(640*360-1):0] addrb;
  
  // evt_counter #(.MAX_COUNT(640*360-1)) bram_in_addr
  // ( .clk_in(clk_100_passthrough),
  //   .rst_in(sys_rst),
  //   .evt_in(y_pix_tvalid),
  //   .count_out(addra),
  //   .hit_max(1'b0) //not using here
  // );

  // logic [7:0] pix_out_raw;
  // logic [7:0] pix_out_hdmi;

  // //Replace FIFO with a BRAM for Video Dislay:
  // //video frame buffer from IP
  // blk_mem_gen_0 video_buffer (
  //   .addra(addra), //pixels are stored using this math
  //   .clka(clk_100_passthrough),
  //   .wea(y_pix_tvalid),
  //   .dina(y_pix_tdata),
  //   .ena(1'b1),
  //   .douta(), //never read from this side
  //   .addrb(addrb),//transformed lookup pixel
  //   .dinb(16'b0),
  //   .clkb(clk_pixel),
  //   .web(1'b0),
  //   .enb(1'b1),
  //   .doutb(pix_out_raw)
    
  // );  

  // logic [(640*360)-1:0] addrb; //used to lookup address in memory for reading from buffer
  // logic               good_addrb; //used to indicate within valid frame for scaling
  // always_ff @(posedge clk_pixel)begin
  //    //2X scaling from frame buffer
  //    addrb <= (hcount_hdmi>>1) + 360*(vcount_hdmi>>1); //Shift to divide by 2
  //    good_addrb <=(hcount_hdmi<640)&&(vcount_hdmi<360); //change me
  //    pix_out_hdmi <= good_addrb ? pix_out_raw : 8'b0;
  // end

  /*
    LINE BUFFER (clk_pixel, 74.25 MHz) + 
    ANTI-ALIASING GAUSSIAN BLUR (clk_pixel, 74.25 MHz)
  */

  // logic [10:0] blur_hcount;  //hcount from blur module
  // logic [9:0] blur_vcount; //vcount from blur module
  // logic [15:0] blur_pixel; //pixel data from blur module //NOW 8-bit?
  // logic blur_valid; //valid signals for blur module
  // //full resolution filter
  // blur_filter #(.HRES(1280),.VRES(720))
  //   blur(
  //   .clk_in(clk_pixel), 
  //   .rst_in(sys_rst_pixel),
  //   .data_valid_in(cdc_valid2),
  //   .pixel_data_in(cdc_pixel), // 16 bits -- now 8?
  //   .hcount_in(cdc_hcount), // 11 bits
  //   .vcount_in(cdc_vcount), // 10 bits
  //   .data_valid_out(blur_valid), 
  //   .pixel_data_out(blur_pixel), // 16 bits -- now 8?
  //   .hcount_out(blur_hcount), // 11 bits
  //   .vcount_out(blur_vcount) // 10 bits
  // );


  /*
    DOWNSAMPLING 
    720 x 1280 -> 360 x 640 
  // */
  // logic should_pack;
  // // downsample (take every other pixel from every other row)
  // // only pack into spi on the valid output cycle
  // assign should_pack = (cdc_hcount2[0] == 1'b0) &&
  //                      (cdc_vcount2[0] == 1'b0) && 
  //                       cdc_valid2;

  // /*
  //   SPI CONVERSION (clk_100mhz, 100 MHz)
  // */
  // logic [5:0][7:0] pixels_to_send;
  // always_ff @(posedge clk_100mhz) begin
  //   if (should_pack) begin
  //     pixels_to_send <= {pixels_to_send[5:0], cdc_pixel2};
  //   end
  // end

  // logic packet_ready;
  // evt_counter #(
  //   .MAX_COUNT(6)
  // ) packet_ready_counter (
  //   .clk_in(clk_100mhz),
  //   .rst_in(sys_rst),
  //   .evt_in(should_pack),
  //   .hit_max(packet_ready)
  // );

  // spi_send_con # (
  //   .DATA_WIDTH(8), // each line should send the 16 bit pixel
  //   .LINES(4), // six parallel lines
  //   .DATA_CLK_PERIOD(6), // 16.6 MHz SPI Clock
  // ) spi_send (
  //   .clk_in(clk_100mhz),
  //   .rst_in(sys_rst),
  //   .data_in(pixels_to_send), // LINES arrays of length DATA_WIDTH bits
  //   .trigger_in(packet_ready),

  //   .chip_data_out(copi), // 6 bits (1 bit from each of the 6 pixels)
  //   .chip_clk_out(dclk),
  //   .chip_sel_out(cs)
  // );

    always_ff @(posedge clk_camera) begin


    end

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

  logic [9:0] tmds_10b [0:2]; //output of each TMDS encoder!
  logic       tmds_signal [2:0]; //output of each TMDS serializer!

   tmds_encoder tmds_red(
       .clk_in(clk_pixel),
       .rst_in(sys_rst_pixel),
       .data_in(y_pix_tdata),
       .control_in(2'b0),
       .ve_in(active_draw_hdmi),
       .tmds_out(tmds_10b[2]));
   tmds_encoder tmds_green(
         .clk_in(clk_pixel),
         .rst_in(sys_rst_pixel),
         .data_in(y_pix_tdata),
         .control_in(2'b0),
         .ve_in(active_draw_hdmi),
         .tmds_out(tmds_10b[1]));
   tmds_encoder tmds_blue(
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .data_in(y_pix_tdata),
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


  // If the camera is not giving data, press your reset button.

   logic  busy, bus_active;
   logic  cr_init_valid, cr_init_ready;
 
   logic  recent_reset;
   always_ff @(posedge clk_camera) begin
     if (sys_rst_camera) begin
       recent_reset <= 1'b1;
       cr_init_valid <= 1'b0;
     end
     else if (recent_reset) begin
       cr_init_valid <= 1'b1;
       recent_reset <= 1'b0;
     end else if (cr_init_valid && cr_init_ready) begin
       cr_init_valid <= 1'b0;
     end
   end

   logic [23:0] bram_dout;
   logic [7:0]  bram_addr;
 
   // ROM holding pre-built camera settings to send
   xilinx_single_port_ram_read_first
     #(
     .RAM_WIDTH(24),
     .RAM_DEPTH(256),
     .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
     .INIT_FILE("rom_640_360.mem")
   ) registers
       (
     .addra(bram_addr),     // Address bus, width determined from RAM_DEPTH
     .dina(24'b0),          // RAM input data, width determined from RAM_WIDTH
     .clka(clk_camera),     // Clock
     .wea(1'b0),            // Write enable
     .ena(1'b1),            // RAM Enable, for additional power savings, disable port when not in use
     .rsta(sys_rst_camera), // Output reset (does not affect memory contents)
     .regcea(1'b1),         // Output register enable
     .douta(bram_dout)      // RAM output data, width determined from RAM_WIDTH
   );
 
   logic [23:0] registers_dout;
   logic [7:0]  registers_addr;
   assign registers_dout = bram_dout;
   assign bram_addr = registers_addr;
 
   logic       con_scl_i, con_scl_o, con_scl_t;
   logic       con_sda_i, con_sda_o, con_sda_t;
 

  // NOTE these also have pullup specified in the xdc file!
  // access our inouts properly as tri-state pins
  IOBUF IOBUF_scl (.I(con_scl_o), .IO(i2c_scl), .O(con_scl_i), .T(con_scl_t) );
  IOBUF IOBUF_sda (.I(con_sda_o), .IO(i2c_sda), .O(con_sda_i), .T(con_sda_t) );

  // provided module to send data BRAM -> I2C
  camera_registers crw
    (.clk_in(clk_camera),
    .rst_in(sys_rst_camera),
    .init_valid(cr_init_valid),
    .init_ready(cr_init_ready),
    .scl_i(con_scl_i),
    .scl_o(con_scl_o),
    .scl_t(con_scl_t),
    .sda_i(con_sda_i),
    .sda_o(con_sda_o),
    .sda_t(con_sda_t),
    .bram_dout(registers_dout),
    .bram_addr(registers_addr));

  // a handful of debug signals for writing to registers
  // assign led[0] = 0;
  // assign led[1] = cr_init_valid;
  // assign led[2] = cr_init_ready;
  // assign led[15:3] = 0;

 
endmodule // top_level
 