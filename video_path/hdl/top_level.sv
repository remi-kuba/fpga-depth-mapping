`timescale 1ns / 1ps
`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 

module top_level(
    input wire clk_100mhz, //100 MHz onboard clock
    input wire [15:0] sw, //all 16 input slide switches
    input wire [3:0] btn, //all four momentary button switches

    // HDMI
    output logic [2:0] hdmi_tx_p, //hdmi output signals (positives) (blue, green, red)
    output logic [2:0] hdmi_tx_n, //hdmi output signals (negatives) (blue, green, red)
    output logic hdmi_clk_p, hdmi_clk_n, //differential hdmi clock

    // SPI 
    input wire dclk, // data clock input from peripheral SPI
    input wire [3:0] cipo, // six parallel data input from peripheral SPI
    input wire cs, // chip select line for the SPI bus
    input wire spi_hsync,
    input wire spi_vsync
  );
 
  //have btn[0] control system reset
  logic sys_rst;
  assign sys_rst = btn[0];

  logic          clk_camera;
  logic          clk_pixel;
  logic          clk_5x;
  logic          clk_xc;

  logic          clk_100_passthrough;

  // clocking wizards to generate the clock speeds we need for our different domains
  // clk_camera: 200MHz, fast enough to comfortably sample the cameera's PCLK (50MHz)
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

  /*
    SPI RECEIVER (clk_100mhz, 100 MHz)
  */

  logic [7:0] received_package [3:0];
  logic received_data_valid;

  spi_receive_con #(
    .DATA_WIDTH(8),
    .LINES(4),
    .DATA_CLK_PERIOD(6)
  ) spi_receive (
    .clk_in(clk_100_passthrough),
    .rst_in(sys_rst),
    .chip_data_in(cipo),
    .chip_clk_in(dclk),
    .chip_sel_in(cs),
    .data_out(received_package),
    .data_valid_out(received_data_valid)
  );


  localparam HSIZE = 640;
  localparam VSIZE = 360;
  logic [9:0] hcount;
  logic [8:0] vcount;
  logic prev_hsync;
  logic [1:0] idx;
  
  always_ff @(posedge clk_100_passthrough) begin
    if (sys_rst) begin
      hcount <= 10'b0;
      vcount <= 9'b0;
      prev_hsync <= 1'b0;
      idx <= 2'b0;
    end else begin
      prev_hsync <= spi_hsync;

      if (received_data_valid) begin
        idx <= 2'b0;
      end

      hcount <= (spi_hsync && spi_vsync)? hcount + 1 : -1;
      vcount <= (!spi_vsync)? 0 :
                (!spi_hsync && prev_hsync)? vcount + 1 :
                                            vcount;
    end
  end



  localparam FB_DEPTH = 640*360;
  localparam FB_SIZE = $clog2(FB_DEPTH);
  logic [FB_SIZE-1:0] addra; //used to specify address to write to in frame buffer
  logic valid_camera_mem; //used to enable writing pixel data to frame buffer
  logic [7:0] cam_pixel;
  logic [7:0] frame_buff_raw; //data out of frame buffer (565)
  logic [FB_SIZE-1:0] addrb; //used to lookup address in memory for reading from buffer

  always_ff @(posedge clk_100_passthrough) begin
    addra <= hcount + (vcount * 640);
    valid_camera_mem <= (idx != 0) || received_data_valid;
    idx <= ((idx == 0 && !received_data_valid) || idx == 3)? 0 : idx + 1;
    cam_pixel <= received_package[idx];
  end 

  blk_mem_gen_0 frame_buffer (
    .addra(addra), //pixels are stored using this math
    .clka(clk_100_passthrough),
    .wea(valid_camera_mem),
    .dina(cam_pixel),
    .ena(1'b1),
    .douta(), //never read from this side
    .addrb(addrb),//transformed lookup pixel
    .dinb(8'b0),
    .clkb(clk_pixel),
    .web(1'b0),
    .enb(1'b1),
    .doutb(frame_buff_raw)
  );

  always_ff @(posedge clk_pixel) begin
    addrb <= hcount_hdmi_pl[0] + (vcount_hdmi_pl[0] * 640); 
    // good_addrb_pl[0] <= (hcount_hdmi_pl[0] < 640) && (vcount_hdmi_pl[0] < 360); 
  end



  // HDMI video signal generator
  video_sig_gen vsg
  (
   .pixel_clk_in(clk_pixel),
   .rst_in(sys_rst),
   .hcount_out(hcount_hdmi_pl[0]),
   .vcount_out(vcount_hdmi_pl[0]),
   .vs_out(vsync_hdmi_pl[0]),
   .hs_out(hsync_hdmi_pl[0]),
   .nf_out(nf_hdmi_pl[0]),
   .ad_out(active_draw_hdmi_pl[0]),
   .fc_out(frame_count_hdmi)
   );

  // video signal generator signals
  logic          hsync_hdmi_pl [2:0];
  logic          vsync_hdmi_pl [2:0];
  logic [9:0]    hcount_hdmi_pl [2:0];
  logic [8:0]    vcount_hdmi_pl [2:0];
  logic          active_draw_hdmi_pl [2:0];
  logic [5:0]    frame_count_hdmi;
  logic          nf_hdmi_pl [2:0];

  always_ff @(posedge clk_pixel) begin
    for (integer i = 1; i < 3; i = i + 1) begin
      hsync_hdmi_pl[i] <= hsync_hdmi_pl[i - 1];
      vsync_hdmi_pl[i] <= vsync_hdmi_pl[i - 1];
      hcount_hdmi_pl[i] <= hcount_hdmi_pl[i - 1];
      vcount_hdmi_pl[i] <= vcount_hdmi_pl[i - 1];
      active_draw_hdmi_pl[i] <= active_draw_hdmi_pl[i - 1];
      nf_hdmi_pl[i] <= nf_hdmi_pl[i - 1];
    end
  end

 
  logic [9:0] tmds_10b [0:2]; //output of each TMDS encoder!
  logic       tmds_signal [2:0]; //output of each TMDS serializer!
  tmds_encoder tmds_red(
    .clk_in(clk_pixel),
    .rst_in(sys_rst),
    .data_in(frame_buff_raw),
    .control_in(2'b0),
    .ve_in(active_draw_hdmi_pl[2]),
    .tmds_out(tmds_10b[2]));

  tmds_encoder tmds_green(
    .clk_in(clk_pixel),
    .rst_in(sys_rst),
    .data_in(frame_buff_raw),
    .control_in(2'b0),
    .ve_in(active_draw_hdmi_pl[2]),
    .tmds_out(tmds_10b[1]));

  tmds_encoder tmds_blue(
    .clk_in(clk_pixel),
    .rst_in(sys_rst),
    .data_in(frame_buff_raw),
    .control_in({vsync_hdmi_pl[2],hsync_hdmi_pl[2]}),
    .ve_in(active_draw_hdmi_pl[2]),
    .tmds_out(tmds_10b[0]));

  tmds_serializer red_ser(
    .clk_pixel_in(clk_pixel),
    .clk_5x_in(clk_5x),
    .rst_in(sys_rst),
    .tmds_in(tmds_10b[2]),
    .tmds_out(tmds_signal[2]));
  tmds_serializer green_ser(
    .clk_pixel_in(clk_pixel),
    .clk_5x_in(clk_5x),
    .rst_in(sys_rst),
    .tmds_in(tmds_10b[1]),
    .tmds_out(tmds_signal[1]));
  tmds_serializer blue_ser(
    .clk_pixel_in(clk_pixel),
    .clk_5x_in(clk_5x),
    .rst_in(sys_rst),
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
endmodule // top_level
 

`default_nettype wire