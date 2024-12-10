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
  // seven segment
  output logic [3:0]  ss0_an,//anode control for upper four digits of seven-seg display
  output logic [3:0]  ss1_an,//anode control for lower four digits of seven-seg display
  output logic [6:0]  ss0_c, //cathode controls for the segments of upper four digits
  output logic [6:0]  ss1_c, //cathod controls for the segments of lower four digits
  // hdmi port
  output logic [2:0]  hdmi_tx_p, //hdmi output signals (positives) (blue, green, red)
  output logic [2:0]  hdmi_tx_n, //hdmi output signals (negatives) (blue, green, red)
  output logic        hdmi_clk_p, hdmi_clk_n, //differential hdmi clock
  // SPI 
  output logic dclk, // data clock output of SPI controller
  output logic [3:0] cipo, // six parallel data outputs of SPI controller
  output logic cs, // chip select line for the SPI bus
  output logic tlast,
  output logic spi_vsync
);

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
  
  cw_hdmi_clk_wiz wizard_hdmi (
    .sysclk(clk_100_passthrough),
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
  always_ff @(posedge clk_camera) begin
    if (sys_rst_camera) begin
      rgb0 <= 3'b001;
    // end else if (check && good_addrb[2]) begin
    end else if (check && trigger) begin
      rgb0 <= 3'b100;
    end 

    if (sys_rst_camera) begin
      rgb1 <= 3'b001;
    // end else if (read_from) begin
    end else if (read_request) begin
      rgb1 <= 3'b100;
    end
  end

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
    DOUBLE BUFFER
  */
  localparam FB_DEPTH = 320*180;
  localparam FB_SIZE = $clog2(FB_DEPTH);
  logic [FB_SIZE-1:0] addra; //used to specify address to write to in frame buffer
  logic valid_camera_mem; //used to enable writing pixel data to frame buffer
  logic [7:0] camera_mem; //used to pass pixel data into frame buffer

  always_ff @(posedge clk_camera) begin
    addra <= camera_hcount[9:1] + (camera_vcount[8:1] * 320);
    valid_camera_mem <= (camera_hcount[0] == 0) && (camera_vcount[0] == 0) && camera_valid;
    camera_mem <= camera_pixel;
  end

  blk_mem_gen_1 frame_buffer (
    .addra(addra), 
    .clka(clk_camera),
    .wea(valid_camera_mem),
    .dina(camera_mem),
    .ena(1'b1),
    .douta(), //never read from this side
    .addrb(addrb),//transformed lookup pixel
    .dinb(16'b0),
    .clkb(clk_100_passthrough),
    .web(1'b0),
    .enb(1'b1),
    .doutb(spi_pixel)
  );
  logic [7:0] spi_pixel;
  logic [FB_SIZE-1:0] addrb;
  always_ff @(posedge clk_100_passthrough) begin
    addrb <= hcount_spi[0] + (vcount_spi[0] * 320);
    for (int i = 1; i < 4; i++) begin
      hcount_spi[i] <= hcount_spi[i-1];
      vcount_spi[i] <= vcount_spi[i-1];
    end
  end
  logic [8:0] hcount_spi [3:0];
  logic [7:0] vcount_spi [3:0];
  logic read_request;
  bram_counter #(
    .MAX_COUNT(12) // data clock period * 2 
  ) bc (
    .clk_in(clk_100_passthrough),
    .rst_in(sys_rst_camera),
    .hit_max_out(trigger),
    .read_request_out(read_request)
  );
  evt_counter #(
    .MAX_COUNT(320)
  ) hcounter (
    .clk_in(clk_100_passthrough),
    .rst_in(sys_rst_camera),
    .evt_in(read_request),
    .count_out(hcount_spi[0])
  );
  evt_counter #(
    .MAX_COUNT(180)
  ) vcounter (
    .clk_in(clk_100_passthrough),
    .rst_in(sys_rst_camera),
    .evt_in(read_request && (hcount_spi[0] == 319)),
    .count_out(vcount_spi[0])
  );


  /*
    SPI SENDER
  */
  logic check;
  logic trigger;
  // assign trigger = camera_valid && (camera_hcount[1:0] == 0) && (camera_vcount[1:0] == 0);
  spi_send_con_2 #(
    .DATA_WIDTH(8),
    .LINES(4),
    // .DATA_CLK_PERIOD(14) // 200 MHz / 12 = 16.6 MHz SPI clock
    .DATA_CLK_PERIOD(6)
  ) spi_send (
    // .clk_in(clk_camera),
    .clk_in(clk_100_passthrough),
    .rst_in(sys_rst_camera),
    // .data_in(camera_pixel),
    .data_in(spi_pixel),
    .trigger_in(trigger),
    // .trigger_in(good_addrb[2]),
    // .hcount_in(camera_hcount),
    // .vcount_in(camera_vcount),
    .hcount_in(hcount_spi[3]),
    .vcount_in(vcount_spi[3]),
    .turn_off_cipo_in(sw[15]), // DEBUGGING

    .half_pixel_ready(check), // DEBUGGING
    .final_pixel_out(tlast),
    .chip_data_out(cipo),
    .chip_clk_out(dclk),
    .chip_sel_out(cs)
  );








  /*
  VIDEO STUFF
  */

  // localparam FB_DEPTH = 320*180;
  // localparam FB_SIZE = $clog2(FB_DEPTH);
  logic [FB_SIZE-1:0] addra2; //used to specify address to write to in frame buffer

  logic valid_camera_mem2; //used to enable writing pixel data to frame buffer
  logic [7:0] camera_mem2; //used to pass pixel data into frame buffer

  always_ff @(posedge clk_camera)begin
    addra2 <= camera_hcount[9:1] + (camera_vcount[8:1] * 320);
    valid_camera_mem2 <= (camera_hcount[0] == 1'b0) && (camera_vcount[0] == 1'b0) && camera_valid; 
    camera_mem2 <= camera_pixel;
  end
  blk_mem_gen_0 frame_buffer2 (
    .addra(addra2), //pixels are stored using this math
    .clka(clk_camera),
    .wea(valid_camera_mem2),
    .dina(camera_mem2),
    .ena(1'b1),
    .douta(), //never read from this side
    .addrb(addrb2),//transformed lookup pixel
    .dinb(16'b0),
    .clkb(clk_pixel),
    .web(1'b0),
    .enb(1'b1),
    .doutb(frame_buff_raw2)
  );
  logic [15:0] frame_buff_raw2; //data out of frame buffer (565)
  logic [FB_SIZE-1:0] addrb2; //used to lookup address in memory for reading from buffer
  logic good_addrb_pl [2:0];
  always_ff @(posedge clk_pixel)begin
    addrb2 <= hcount_hdmi_pl[0] + (vcount_hdmi_pl[0] * 320); 
    good_addrb_pl[0] <= (hcount_hdmi_pl[0] < 320) && (vcount_hdmi_pl[0] < 180); 
    good_addrb_pl[1] <= good_addrb_pl[0];
    good_addrb_pl[2] <= good_addrb_pl[1];
  end
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
  logic [7:0]          red,green,blue;
  always_ff @(posedge clk_pixel)begin
    red <= good_addrb_pl[2]?{frame_buff_raw2[7:0]}:8'h9C;
    green <= good_addrb_pl[2]?{frame_buff_raw2[7:0]}:8'h27;
    blue <= good_addrb_pl[2]?{frame_buff_raw2[7:0]}:8'hB0;
  end
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
  // assign led[15:3] = 0;

endmodule // top_level


`default_nettype wire

