`timescale 1ns / 1ps
`default_nettype none

module top_level
  (
  input wire          clk_100mhz,
  output logic [15:0] led,
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
  // spi
  input wire cs,
  input wire dclk,
  input wire [3:0] cipo,
  input wire spi_tlast,
  input wire spi_vsync,
  // seven segment
  output logic [3:0]  ss0_an,//anode control for upper four digits of seven-seg display
  output logic [3:0]  ss1_an,//anode control for lower four digits of seven-seg display
  output logic [6:0]  ss0_c, //cathode controls for the segments of upper four digits
  output logic [6:0]  ss1_c, //cathod controls for the segments of lower four digits
  // hdmi port
  output logic [2:0]  hdmi_tx_p, //hdmi output signals (positives) (blue, green, red)
  output logic [2:0]  hdmi_tx_n, //hdmi output signals (negatives) (blue, green, red)
  output logic        hdmi_clk_p, hdmi_clk_n, //differential hdmi clock
  // New for week 6: DDR3 ports
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

  // shut up those RGBs
  // assign rgb0 = 0;
  // assign rgb1 = 0;

  // Clock and Reset Signals: updated for a couple new clocks!
  logic          sys_rst_camera;
  logic          sys_rst_pixel;

  logic          clk_camera;
  logic          clk_pixel;
  logic          clk_5x;
  logic          clk_xc;


  logic          clk_migref;
  logic          sys_rst_migref;
  
  logic          clk_ui;
  logic          sys_rst_ui;
  
  logic          clk_100_passthrough;

  // clocking wizards to generate the clock speeds we need for our different domains
  // clk_camera: 200MHz, fast enough to comfortably sample the cameera's PCLK (50MHz)
  cw_hdmi_clk_wiz wizard_hdmi
    (.sysclk(clk_100_passthrough),
    .clk_pixel(clk_pixel),
    .clk_tmds(clk_5x),
    .reset(0));

  cw_fast_clk_wiz wizard_migcam(
    .clk_in1(clk_100mhz),
    .clk_camera(clk_camera),
    .clk_mig(clk_migref),
    .clk_xc(clk_xc),
    .clk_100(clk_100_passthrough),
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

  // ** Handling input from the camera **

  // synchronizers to prevent metastability
  logic [7:0]    camera_d_buf [1:0];
  logic          cam_hsync_buf [1:0];
  logic          cam_vsync_buf [1:0];
  logic          cam_pclk_buf [1:0];

  always_ff @(posedge clk_camera) begin
    camera_d_buf[1] <= {<<{camera_d}};
    camera_d_buf[0] <= camera_d_buf[1];
    cam_pclk_buf[1] <= cam_pclk;
    cam_pclk_buf[0] <= cam_pclk_buf[1];
    cam_hsync_buf[1] <= cam_hsync;
    cam_hsync_buf[0] <= cam_hsync_buf[1];
    cam_vsync_buf[1] <= cam_vsync;
    cam_vsync_buf[0] <= cam_vsync_buf[1];
  end

  logic [9:0] camera_hcount;
  logic [8:0]  camera_vcount;
  logic [7:0] camera_pixel;
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
    .pixel_data_out(camera_pixel)
  );


  /*
    SPI synchronizers
  */
  // ** Handling input from the other camera **
  logic received_data_valid;
  logic received_package;
  logic [7:0] received_pixel;
  logic received_pixel_valid;
  logic final_pixel;

  logic [3:0] cipo_buf [1:0];
  logic [1:0] dclk_buf;
  logic [1:0] spi_tlast_buf;
  logic [1:0] cs_buf;
  always_ff @(posedge clk_100_passthrough) begin
    cipo_buf[0] <= cipo;
    cipo_buf[1] <= cipo_buf[0];
    dclk_buf[0] <= dclk;
    dclk_buf[1] <= dclk_buf[0];
    spi_tlast_buf[0] <= spi_tlast;
    spi_tlast_buf[1] <= spi_tlast_buf[0];
    cs_buf[0] <= cs;
    cs_buf[1] <= cs_buf[0];
  end

  spi_receive_con_2 #(
    .DATA_WIDTH(8),
    .LINES(4)
  ) spi_receive (
    .clk_in(clk_100_passthrough),
    .rst_in(sys_rst_camera),
    .chip_data_in(cipo_buf[1]),
    .chip_clk_in(dclk_buf[1]),
    .chip_sel_in(cs_buf[1]),
    .final_pixel_in(spi_tlast_buf[1]),
    .final_pixel_out(final_pixel),
    .data_out(received_pixel),
    .data_valid_out(received_pixel_valid));


  // Two ways to store a frame buffer: subsampled BRAM, and full-quality DRAM.
  
  logic [7:0] frame_buff_raw; // select between the two!
 
  // 2. The New Way: write memory to DRAM and read it out, over a couple AXI-Stream data pipelines.
  // NEW DRAM STUFF STARTS HERE


  logic [127:0] camera_chunk;
  logic [127:0] camera_axis_tdata;
  logic         camera_axis_tlast;
  logic         camera_axis_tready;
  logic         camera_axis_tvalid;

  // takes our 16-bit values and deserialize/stack them into 128-bit messages to write to DRAM
  // the data pipeline is designed such that we can fairly safely assume its always ready.
  stacker stacker_inst(
    .clk_in(clk_100_passthrough),
    .rst_in(sys_rst_camera),
    // .pixel_tvalid(stacked_pixel_valid),
    // .pixel_tvalid(camera_valid),
    // .pixel_tvalid(received_data_valid),
    .pixel_tvalid(received_pixel_valid),
    .pixel_tready(),
    // .pixel_tdata(stacked_pixel),
    // .pixel_tdata(camera_pixel),
    // .pixel_tdata(received_package),
    .pixel_tdata(received_pixel),
    // TODO: define the tlast value! you can do it in one line, based on camera hcount/vcount values
    .pixel_tlast(final_pixel && received_pixel_valid), // change me
    .chunk_tvalid(camera_axis_tvalid),
    .chunk_tready(camera_axis_tready),
    .chunk_tdata(camera_axis_tdata),
    .chunk_tlast(camera_axis_tlast));
  
  logic [127:0] camera_ui_axis_tdata;
  logic         camera_ui_axis_tlast;
  logic         camera_ui_axis_tready;
  logic         camera_ui_axis_tvalid;
  logic         camera_ui_axis_prog_empty;

  // FIFO data queue of 128-bit messages, crosses clock domains to the 81.25MHz
  // UI clock of the memory interface
  ddr_fifo_wrap camera_data_fifo(
    .sender_rst(sys_rst_camera),
    .sender_clk(clk_100_passthrough),
    .sender_axis_tvalid(camera_axis_tvalid),
    .sender_axis_tready(camera_axis_tready),
    .sender_axis_tdata(camera_axis_tdata),
    .sender_axis_tlast(camera_axis_tlast),
    .receiver_clk(clk_ui),
    .receiver_axis_tvalid(camera_ui_axis_tvalid),
    .receiver_axis_tready(camera_ui_axis_tready),
    .receiver_axis_tdata(camera_ui_axis_tdata),
    .receiver_axis_tlast(camera_ui_axis_tlast),
    .receiver_axis_prog_empty(camera_ui_axis_prog_empty));

  logic [127:0] display_ui_axis_tdata;
  logic         display_ui_axis_tlast;
  logic         display_ui_axis_tready;
  logic         display_ui_axis_tvalid;
  logic         display_ui_axis_prog_full;

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
    .write_axis_ready (camera_ui_axis_tready),
    .read_axis_data   (display_ui_axis_tdata),
    .read_axis_tlast  (display_ui_axis_tlast),
    .read_axis_valid  (display_ui_axis_tvalid),
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
    .write_axis_data  (camera_ui_axis_tdata),
    .write_axis_tlast (camera_ui_axis_tlast),
    .write_axis_valid (camera_ui_axis_tvalid),
    .write_axis_smallpile(camera_ui_axis_prog_empty),
    .read_axis_af     (display_ui_axis_prog_full),
    .read_axis_ready  (display_ui_axis_tready) //,
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
  
  logic [127:0] display_axis_tdata;
  logic         display_axis_tlast;
  logic         display_axis_tready;
  logic         display_axis_tvalid;
  logic         display_axis_prog_empty;
  
  ddr_fifo_wrap pdfifo(
    .sender_rst(sys_rst_ui),
    .sender_clk(clk_ui),
    .sender_axis_tvalid(display_ui_axis_tvalid),
    .sender_axis_tready(display_ui_axis_tready),
    .sender_axis_tdata(display_ui_axis_tdata),
    .sender_axis_tlast(display_ui_axis_tlast),
    .sender_axis_prog_full(display_ui_axis_prog_full),
    .receiver_clk(clk_pixel),
    .receiver_axis_tvalid(display_axis_tvalid),
    .receiver_axis_tready(display_axis_tready),
    .receiver_axis_tdata(display_axis_tdata),
    .receiver_axis_tlast(display_axis_tlast),
    .receiver_axis_prog_empty(display_axis_prog_empty));

  logic frame_buff_tvalid;
  logic frame_buff_tready;
  logic [7:0] frame_buff_tdata;
  logic        frame_buff_tlast;

  unstacker unstacker_inst(
    .clk_in(clk_pixel),
    .rst_in(sys_rst_pixel),
    .chunk_tvalid(display_axis_tvalid),
    .chunk_tready(display_axis_tready),
    .chunk_tdata(display_axis_tdata),
    .chunk_tlast(display_axis_tlast),
    .pixel_tvalid(frame_buff_tvalid),
    .pixel_tready(frame_buff_tready),
    .pixel_tdata(frame_buff_tdata),
    .pixel_tlast(frame_buff_tlast));

  // TODO: assign frame_buff_tready
  // I did this in 1 (kind of long) line. an always_comb block could also work.
  always_comb begin
    if (frame_buff_tlast) begin
      frame_buff_tready = active_draw_hdmi && (hcount_hdmi == 639) && (vcount_hdmi == 359);
      // frame_buff_tready = active_draw_hdmi && (hcount_hdmi == 159) && (vcount_hdmi == 89);
      // frame_buff_tready = active_draw_hdmi && (hcount_hdmi == 319) && (vcount_hdmi == 179);
    end else begin
      frame_buff_tready = active_draw_hdmi && (hcount_hdmi < 640) && (vcount_hdmi < 360);
      // frame_buff_tready = active_draw_hdmi && (hcount_hdmi < 160) && (vcount_hdmi < 90);
      // frame_buff_tready = active_draw_hdmi && (hcount_hdmi < 320) && (vcount_hdmi < 180);
    end
  end
  // TODO in part 2: update this tready to also only be high for odd hcount values (every other drawn pixel gets a new value)

  
  assign frame_buff_raw = frame_buff_tvalid ? frame_buff_tdata : 8'h27;

  // NEW DRAM STUFF ENDS HERE: below here should look familiar from last week!

  // HDMI video signal generator
  video_sig_gen vsg (
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

  logic is_a_pixel_addr;
  always_comb begin
    is_a_pixel_addr = (hcount_hdmi < 640) && (vcount_hdmi < 360) && active_draw_hdmi;
    // is_a_pixel_addr = (hcount_hdmi < 160) && (vcount_hdmi < 90) && active_draw_hdmi;
    // is_a_pixel_addr = (hcount_hdmi < 320) && (vcount_hdmi < 180) && active_draw_hdmi;
    red = (is_a_pixel_addr)? frame_buff_raw : 8'hA3;
    green = (is_a_pixel_addr)? frame_buff_raw : 8'hF4;
    blue = (is_a_pixel_addr)? frame_buff_raw : 8'hBF;
  end

  // HDMI Output: just like before!

  logic [9:0] tmds_10b [0:2]; //output of each TMDS encoder!
  logic       tmds_signal [2:0]; //output of each TMDS serializer!

  //three tmds_encoders (blue, green, red)
  //note green should have no control signal like red
  //the blue channel DOES carry the two sync signals:
  //  * control_in[0] = horizontal sync signal
  //  * control_in[1] = vertical sync signal

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


  //three tmds_serializers (blue, green, red):
  //MISSING: two more serializers for the green and blue tmds signals.
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

  //output buffers generating differential signals:
  //three for the r,g,b signals and one that is at the pixel clock rate
  //the HDMI receivers use recover logic coupled with the control signals asserted
  //during blanking and sync periods to synchronize their faster bit clocks off
  //of the slower pixel clock (so they can recover a clock of about 742.5 MHz from
  //the slower 74.25 MHz clock)
  OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
  OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
  OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
  OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));


  // Nothing To Touch Down Here:
  // register writes to the camera

  // The OV5640 has an I2C bus connected to the board, which is used
  // for setting all the hardware settings (gain, white balance,
  // compression, image quality, etc) needed to start the camera up.
  // We've taken care of setting these all these values for you:
  // "rom.mem" holds a sequence of bytes to be sent over I2C to get
  // the camera up and running, and we've written a design that sends
  // them just after a reset completes.

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
    .INIT_FILE("rom_640_360_new.mem")
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
  assign led[0] = 0;
  assign led[1] = cr_init_valid;
  assign led[2] = cr_init_ready;
  assign led[15:3] = 0;

endmodule // top_level


`default_nettype wire

