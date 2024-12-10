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
  output logic        hdmi_clk_p, hdmi_clk_n //differential hdmi clock
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
  logic           clk_sad;

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

  clk_wiz_half_clk_wiz wizard_sad (
    .clk_in1(clk_100_passthrough),
    .clk_out1(clk_sad),
    .reset(0));

  // assign camera's xclk to pmod port: drive the operating clock of the camera!
  // this port also is specifically set to high drive by the XDC file.
  assign cam_xclk = clk_xc;

  assign sys_rst_camera = btn[0]; //use for resetting camera side of logic
  assign sys_rst_pixel = btn[0]; //use for resetting hdmi/draw side of logic
  assign sys_rst_migref = btn[0];

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

  // when switch 0 is on, stop updating the frame buffers
  // essentially makes the frame static
  logic take_picture;
  assign take_picture = sw[15];
  logic [FB_SIZE-1:0] addra_onboard;
  logic valid_camera_mem;
  logic [7:0] camera_mem;
  always_ff @(posedge clk_camera) begin
    addra_onboard <= camera_hcount[9:1] + (camera_vcount[8:1] * 320);
    valid_camera_mem <= (camera_hcount[0] == 1'b0) && (camera_vcount[0] == 1'b0) && camera_valid; 
    camera_mem <= camera_pixel;
  end
  blk_mem_gen_1 frame_buffer_onboard (
    .addra(addra_onboard), 
    .clka(clk_camera),
    .wea(valid_camera_mem && !take_picture),
    .dina(camera_mem),
    .ena(1'b1),
    .douta(), //never read from this side
    // .addrb((sw[0])? addrb : addrb_onboard),//transformed lookup pixel
    .addrb(addrb),
    .dinb(16'b0),
    .clkb(clk_sad),
    .web(1'b0),
    .enb(1'b1),
    .doutb(onboard_pixel)
  );
  logic [7:0] onboard_pixel;

  // logic [FB_SIZE-1:0] addrb_onboard;
  // logic good_addrb_pl_onboard [2:0];
  // always_ff @(posedge clk_sad) begin
  //   addrb_onboard <= (hcount_hdmi_pl[0] - 320) + (vcount_hdmi_pl[0] * 320); 
  //   good_addrb_pl_onboard[0] <= (hcount_hdmi_pl[0] >= 320) && (hcount_hdmi_pl[0] < 640) && (vcount_hdmi_pl[0] < 180); 
  //   good_addrb_pl_onboard[1] <= good_addrb_pl_onboard[0];
  //   good_addrb_pl_onboard[2] <= good_addrb_pl_onboard[1];
  // end



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

  logic [8:0] hcount_spi;
  logic [7:0] vcount_spi;
  addr_counter # (
    .HCOUNT(320),
    .VCOUNT(180)
  ) spi_address (
    .clk_in(clk_100_passthrough),
    .rst_in(final_pixel || sys_rst_camera),
    .evt_in(received_pixel_valid),
    .hcount_out(hcount_spi),
    .vcount_out(vcount_spi));
  

  localparam FB_DEPTH = 320*180;
  localparam FB_SIZE = $clog2(FB_DEPTH);
  logic [FB_SIZE-1:0] addra_spi;

  assign addra_spi = hcount_spi + (vcount_spi * 320);
  // Two ways to store a frame buffer: subsampled BRAM, and full-quality DRAM.
  blk_mem_gen_1 frame_buffer_spi (
    .addra(addra_spi), 
    .clka(clk_100_passthrough),
    .wea(received_pixel_valid && !take_picture),
    .dina(received_pixel),
    .ena(1'b1),
    .douta(), //never read from this side
    // .addrb((sw[0])? addrb : addrb_spi),//transformed lookup pixel
    .addrb(addrb),
    .dinb(16'b0),
    .clkb(clk_sad),
    .web(1'b0),
    .enb(1'b1),
    .doutb(spi_pixel));

  logic [7:0] spi_pixel;

  // logic [FB_SIZE-1:0] addrb_spi;
  // logic good_addrb_pl_spi [2:0];
  // always_ff @(posedge clk_sad) begin
  //   addrb_spi <= hcount_hdmi_pl[0] + (vcount_hdmi_pl[0] * 320); 
  //   good_addrb_pl_spi[0] <= (hcount_hdmi_pl[0] < 320) && (vcount_hdmi_pl[0] < 180); 
  //   good_addrb_pl_spi[1] <= good_addrb_pl_spi[0];
  //   good_addrb_pl_spi[2] <= good_addrb_pl_spi[1];
  // end


  logic [FB_SIZE-1:0] addrb;
  always_ff @(posedge clk_sad) begin
    addrb <= hcount_bram[0] + (vcount_bram[0] * 320);
    for (int i = 1; i < 4; i++) begin
      hcount_bram[i] <= hcount_bram[i-1];
      vcount_bram[i] <= vcount_bram[i-1];
      read_request[i] <= read_request[i-1];
    end
  end
  logic [8:0] hcount_bram [3:0];
  logic [7:0] vcount_bram [3:0];
  logic [3:0] read_request;
  // logic trigger;
  bram_counter #(
    .MAX_COUNT(22) // how long it takes to calculate SAD
  ) bc (
    .clk_in(clk_sad),
    .rst_in(sys_rst_camera),
    // .hit_max_out(trigger),
    .read_request_out(read_request[0])
  );
  evt_counter_2 #(
    .MAX_COUNT(320)
  ) hcounter (
    .clk_in(clk_sad),
    .rst_in(sys_rst_camera),
    .evt_in(read_request[0]),
    .count_out(hcount_bram[0])
  );
  evt_counter_2 #(
    .MAX_COUNT(180)
  ) vcounter (
    .clk_in(clk_sad),
    .rst_in(sys_rst_camera),
    .evt_in(read_request[0] && (hcount_bram[0] == 319)),
    .count_out(vcount_bram[0])
  );

  logic [2:0][7:0] onboard_line_buffer;
  logic [2:0][7:0] spi_line_buffer;
  logic onboard_data_valid;
  logic spi_data_valid;
  logic [10:0] onboard_hcount;
  logic [9:0] onboard_vcount;
  logic [10:0] spi_hcount;
  logic [9:0] spi_vcount;
  line_buffer lb_onboard (
    .clk_in(clk_sad),
    .rst_in(sys_rst_pixel),
    .hcount_in(hcount_bram[3]),
    .vcount_in(vcount_bram[3]),
    .pixel_data_in(onboard_pixel),
    .data_valid_in(read_request[3]),
    .line_buffer_out(onboard_line_buffer),
    .hcount_out(onboard_hcount),
    .vcount_out(onboard_vcount),
    .data_valid_out(onboard_data_valid));
  line_buffer lb_spi (
    .clk_in(clk_sad),
    .rst_in(sys_rst_pixel),
    .hcount_in(hcount_bram[3]),
    .vcount_in(vcount_bram[3]),
    .pixel_data_in(spi_pixel),
    .data_valid_in(read_request[3]),
    .line_buffer_out(spi_line_buffer),
    .hcount_out(spi_hcount),
    .vcount_out(spi_vcount),
    .data_valid_out(spi_data_valid));

  sad #(
    .KERNEL_WIDTH(3),
    .OFFSET(10)
  ) sad_module (
    .clk_in(clk_sad),
    .rst_in(sys_rst_pixel),
    .left_data_in(onboard_line_buffer),
    .right_data_in(spi_line_buffer),
    .hcount_in(spi_hcount),
    .vcount_in(spi_vcount),
    // .data_valid_in((spi_hcount == onboard_hcount) && (spi_vcount == onboard_vcount) && 
    //                 spi_data_valid && onboard_data_valid),
    .data_valid_in(spi_data_valid),
    .data_valid_out(sad_valid),
    .busy_out(),
    .hcount_out(sad_hcount),
    .vcount_out(sad_vcount),
    .line_out(sad_pixel));

  logic sad_valid;
  logic [9:0] sad_hcount;
  logic [8:0] sad_vcount;
  logic [7:0] sad_pixel;
  logic [7:0] sad_pixel_store;
  logic [FB_SIZE-1:0] addra_sad;
  always_ff @(posedge clk_sad) begin
    sad_pixel_store <= sad_pixel;
    addra_sad <= sad_hcount + (sad_vcount * 320);
  end
  blk_mem_gen_1 frame_buffer_sad (
    .addra(addra_sad), 
    .clka(clk_sad),
    .wea(sad_valid),
    .dina(sad_pixel_store),
    .ena(1'b1),
    .douta(), //never read from this side
    .addrb(addrb_video),//transformed lookup pixel
    .dinb(16'b0),
    .clkb(clk_pixel),
    .web(1'b0),
    .enb(1'b1),
    .doutb(video_pixel));

  logic [7:0] video_pixel;
  logic [FB_SIZE-1:0] addrb_video;
  logic good_addrb [2:0];
  always_ff @(posedge clk_pixel) begin
    addrb_video <= hcount_hdmi_pl[0] + (vcount_hdmi_pl[0] * 320); 
    good_addrb[0] <= (hcount_hdmi_pl[0] < 320) && (vcount_hdmi_pl[0] < 180); 
    good_addrb[1] <= good_addrb[0];
    good_addrb[2] <= good_addrb[1];
  end






  // HDMI video signal generator
  video_sig_gen vsg (
   .pixel_clk_in(clk_pixel),
   .rst_in(sys_rst_pixel),
   .hcount_out(hcount_hdmi_pl[0]),
   .vcount_out(vcount_hdmi_pl[0]),
   .vs_out(vsync_hdmi_pl[0]),
   .hs_out(hsync_hdmi_pl[0]),
   .nf_out(nf_hdmi_pl[0]),
   .ad_out(active_draw_hdmi_pl[0]),
   .fc_out(frame_count_hdmi)
  );
  logic          hsync_hdmi_pl [4:0];
  logic          vsync_hdmi_pl [4:0];
  logic [10:0]  hcount_hdmi_pl [4:0];
  logic [9:0]    vcount_hdmi_pl [4:0];
  logic          active_draw_hdmi_pl [4:0];
  logic [5:0]    frame_count_hdmi;
  logic          nf_hdmi_pl [4:0];
  always_ff @(posedge clk_pixel) begin
    for (integer i = 1; i < 5; i = i + 1) begin
      hsync_hdmi_pl[i] <= hsync_hdmi_pl[i - 1];
      vsync_hdmi_pl[i] <= vsync_hdmi_pl[i - 1];
      hcount_hdmi_pl[i] <= hcount_hdmi_pl[i - 1];
      vcount_hdmi_pl[i] <= vcount_hdmi_pl[i - 1];
      active_draw_hdmi_pl[i] <= active_draw_hdmi_pl[i - 1];
      nf_hdmi_pl[i] <= nf_hdmi_pl[i - 1];
    end
  end





  /*
  VIDEO OUTPUT FOR TWO VIDEOS
  */
  logic [7:0]          red,green,blue;
  always_ff @(posedge clk_pixel)begin
    // red <= good_addrb_pl_spi[2]? spi_pixel : good_addrb_pl_onboard[2]? onboard_pixel : 8'h9C;
    // green <= good_addrb_pl_spi[2]? spi_pixel : good_addrb_pl_onboard[2]? onboard_pixel : 8'h27;
    // blue <= good_addrb_pl_spi[2]? spi_pixel : good_addrb_pl_onboard[2]? onboard_pixel : 8'hB0;
    // if (sw[0]) begin
      red <= good_addrb[2]? video_pixel : 8'hA3;
      green <= good_addrb[2]? video_pixel : 8'hF4;
      blue <= good_addrb[2]? video_pixel : 8'hBF;
    // end else begin
    //   red <= good_addrb_pl_spi[2]? spi_pixel : good_addrb_pl_onboard[2]? onboard_pixel : 8'h9C;
    //   green <= good_addrb_pl_spi[2]? spi_pixel : good_addrb_pl_onboard[2]? onboard_pixel : 8'h27;
    //   blue <= good_addrb_pl_spi[2]? spi_pixel : good_addrb_pl_onboard[2]? onboard_pixel : 8'hB0;
    // end
  end
  // HDMI Output: just like before!
  logic [9:0] tmds_10b [0:2]; //output of each TMDS encoder!
  logic       tmds_signal [2:0]; //output of each TMDS serializer!
  tmds_encoder tmds_red(
    .clk_in(clk_pixel),
    .rst_in(sys_rst_pixel),
    .data_in(red),
    .control_in(2'b0),
    .ve_in(active_draw_hdmi_pl[4]),
    .tmds_out(tmds_10b[2]));

  tmds_encoder tmds_green(
        .clk_in(clk_pixel),
        .rst_in(sys_rst_pixel),
        .data_in(green),
        .control_in(2'b0),
        .ve_in(active_draw_hdmi_pl[4]),
        .tmds_out(tmds_10b[1]));

  tmds_encoder tmds_blue(
      .clk_in(clk_pixel),
      .rst_in(sys_rst_pixel),
      .data_in(blue),
      .control_in({vsync_hdmi_pl[4],hsync_hdmi_pl[4]}),
      .ve_in(active_draw_hdmi_pl[4]),
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
  logic [8:0]  bram_addr;

  // ROM holding pre-built camera settings to send
  xilinx_single_port_ram_read_first
    #(
    .RAM_WIDTH(24),
    .RAM_DEPTH(512),
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
  logic [8:0]  registers_addr;
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

