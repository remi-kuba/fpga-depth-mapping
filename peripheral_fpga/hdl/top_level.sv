


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

  // SPI 
  output logic dclk, // data clock output of SPI controller
  output logic [3:0] cipo, // six parallel data outputs of SPI controller
  output logic cs, // chip select line for the SPI bus
  output logic spi_hsync,
  output logic spi_vsync
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


  // synchronizers to prevent metastability
  logic [7:0]    camera_d_buf [1:0];
  logic          cam_hsync_buf [1:0];
  logic          cam_vsync_buf [1:0];
  logic          cam_pclk_buf [1:0];

  always_ff @(posedge clk_camera) begin
    camera_d_buf[1] <= camera_d;
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
    end else if (cams_valid) begin
      rgb0 <= 3'b100;
    end 

    if (sys_rst_camera) begin
      rgb1 <= 3'b001;
    end else if (spi_hsyncs) begin
      rgb1 <= 3'b100;
    end
  end

  logic spi_hsync;
  assign spi_hsync = (camera_hcount == 639) && (camera_vcount == 359);

  evt_counter #(
    .MAX_COUNT(1000)
  ) frame_ct (
    .clk_in(clk_camera),
    .rst_in(sys_rst_camera),
    .evt_in(spi_hsync),
    .hit_max_out(spi_hsyncs)
  );
  logic spi_hsyncs;

  evt_counter #(
    .MAX_COUNT(50_000_000)
  ) pixel_valid_ct(
    .clk_in(clk_camera),
    .rst_in(sys_rst_camera),
    .evt_in(camera_valid),
    .hit_max_out(cams_valid)
  );
  logic cams_valid;
  assign led[0] = cams_valid;
  assign led[1] = camera_valid;

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

  // /*
  //   CDC FIFO
  // */
  // logic empty;
  // logic cdc_valid;
  // logic [7:0] cdc_pixel;
  // logic [10:0] cdc_hcount;
  // logic [9:0] cdc_vcount;

  // fifo cdc_fifo
  // (.wr_clk(clk_camera),
  //  .full(),
  //  .din({camera_hcount, camera_vcount, camera_pixel}),
  //  .wr_en(camera_valid && camera_hcount[0] == 0 && camera_vcount[0] == 0),

  //  .rd_clk(clk_100_passthrough),
  //  .empty(empty),
  //  .dout({cdc_hcount, cdc_vcount, cdc_pixel}),
  //  .rd_en(1) //always read
  // );
  // assign cdc_valid = ~empty;


  /*
    SPI SENDER
  */
  logic check;
  logic trigger;
  // assign trigger = cdc_valid;
  assign trigger = camera_valid && (camera_hcount[1:0] == 0) && (camera_vcount[1:0] == 0);
  spi_send_con_2 #(
    .DATA_WIDTH(8),
    .LINES(4),
    .DATA_CLK_PERIOD(12) // 200 MHz / 12 = 16.6 MHz SPI clock
  ) spi_send (
    .clk_in(clk_camera),
    .rst_in(sys_rst_camera),
    .data_in(camera_pixel),
    .trigger_in(trigger),

    .half_pixel_ready(check),
    .chip_data_out(cipo),
    .chip_clk_out(dclk),
    .chip_sel_out(cs)
  );


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


`default_nettype wire

