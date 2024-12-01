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
    CAMERA CLOCKS AND SYNCHRONIZERS
    synchronizers to prevent metastability
  */
  logic       clk_camera;
  cw_fast_clk_wiz wizard_migcam (
    .clk_in1(clk_100mhz),
    .clk_camera(clk_camera),
    .reset(0));

  logic [7:0] camera_d_buf [1:0];
  logic       cam_hsync_buf [1:0];
  logic       cam_vsync_buf [1:0];
  logic       cam_pclk_buf [1:0];

  always_ff @(posedge clk_camera) begin
    camera_d_buf <= {camera_d, camera_d_buf[1]};
    cam_pclk_buf <= {cam_pclk, cam_pclk_buf[1]};
    cam_hsync_buf <= {cam_hsync, cam_hsync_buf[1]};
    cam_vsync_buf <= {cam_vsync, cam_vsync_buf[1]};
  end

  /*
    LUMINANCE RECONSTRUCT
  */
  logic [9:0] camera_hcount;
  logic [8:0] camera_vcount;
  logic [7:0] camera_pixel;
  logic       camera_valid;

  luminance_reconstruct # (
    .HCOUNT_WIDTH(10),
    .VCOUNT_WIDTH(9)
  ) lr (
    .clk_in(clk_camera),
    .rst_in(sys_rst),
    .camera_pclk_in(cam_pclk_buf[0]),
    .camera_hs_in(cam_hsync_buf[0]),
    .camera_vs_in(cam_vsync_buf[0]),
    .camera_data_in(camera_d_buf[0]),
    .pixel_valid_out(camera_valid),
    .pixel_hcount_out(camera_hcount),
    .pixel_vcount_out(camera_vcount),
    .pixel_data_out(camera_pixel));


  /*
    PACKER
  */
  logic [7:0] pixels_to_send [3:0]; // send four 8-bit pixels in parallel

  always_ff @(posedge clk_camera) begin
    if (camera_valid) begin
      pixels_to_send[count_out] <= camera_pixel;
    end 
  end

  logic [1:0] count_out;
  logic       packet_ready;
  evt_counter #(
    .MAX_COUNT(4)
  ) packet_ready_counter (
    .clk_in(clk_100_passthrough),
    .rst_in(sys_rst),
    .evt_in(should_pack),
    .count_out(count_out),
    .hit_max_out(packet_ready));


  /*
    SPI SENDER
  */
  spi_send_con #(
    .DATA_WIDTH(8),
    .LINES(4),
    .DATA_CLK_PERIOD(12) // 200 MHz / 12 = 16.6 MHz SPI clock
  ) spi_send (
    .clk_in(clk_camera),
    .rst_in(sys_rst),
    .data_in(pixels_to_send),
    .trigger_in(packet_ready),

    .chip_data_out(cipo),
    .chip_clk_out(dclk),
    .chip_sel_out(cs)
  );

  // assign spi_hsync = cam_hsync;
  // make spi_hsync actually hold a tlast value
  assign spi_hsync = (camera_hcount == 639) && (camera_vcount == 359);
  assign spi_vsync = cam_vsync;


  /*
    CAMERA STUFF
  */

  logic  busy, bus_active;
  logic  cr_init_valid, cr_init_ready;

  logic  recent_reset;
  always_ff @(posedge clk_camera) begin
    if (sys_rst) begin
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
      .rsta(sys_rst), // Output reset (does not affect memory contents)
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
    .rst_in(sys_rst),
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
  // assign led[0] = crw.bus_active;
  // assign led[1] = cr_init_valid;
  // assign led[2] = cr_init_ready;
  // assign led[15:3] = 0;

endmodule // top_level

`default_nettype wire