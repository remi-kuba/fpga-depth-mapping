`timescale 1ns / 1ps
`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module top_level(
  input wire clk_100mhz, //100 MHz onboard clock
  input wire [15:0] sw, //all 16 input slide switches
  input wire [3:0] btn, //all four momentary button switches
  output logic [15:0] led,
  output logic [2:0] rgb1,
  output logic [2:0] rgb0,

  output logic [3:0] ss0_an,//anode control for upper four digits of seven-seg display
  output logic [3:0] ss1_an,//anode control for lower four digits of seven-seg display
  output logic [6:0] ss0_c, //cathode controls for the segments of upper four digits
  output logic [6:0] ss1_c, //cathode controls for the segments of lower four digits

  // SPI 
  output logic dclk, // data clock output of SPI controller
  output logic [3:0] cipo, // six parallel data outputs of SPI controller
  output logic cs, // chip select line for the SPI bus
  output logic tlast,
  output logic spi_vsync
  );

  logic [31:0] value_to_display;
  logic [6:0] ss_c;
  assign ss0_c = ss_c;
  assign ss1_c = ss_c;
  seven_segment_controller mssc(.clk_in(clk_100_passthrough),
                               .rst_in(sys_rst),
                               .val_in(value_to_display),
                               .cat_out(ss_c),
                               .an_out({ss0_an, ss1_an}));

  logic clk_100_passthrough, clk_camera;
  cw_fast_clk_wiz wizard_migcam(
    .clk_in1(clk_100mhz),
    .clk_camera(clk_camera),
    .clk_100(clk_100_passthrough),
    .reset(0));
  // assign rgb0 = sw[2:0];
  // assign rgb1 = sw[5:3];
  /*
    RESETS
  */
  // btn[0] controls system reset
  logic sys_rst;
  assign sys_rst = btn[0];
  // assign cipo = sw[4:1];
  // assign spi_hsync = sw[15];
  // assign spi_vsync = sw[14];

  assign led = sw;
  assign rgb0 = 0;
  logic [7:0] pixel_to_send;
  logic pixel_ready;
  logic previous_sw;
  // assign spi_hsync = sw[0];
  always_ff @(posedge clk_camera) begin
    if (sys_rst) begin
      pixel_ready <= 1'b0;
      pixel_to_send <= 8'b0;
      value_to_display <= 32'b0;
      rgb1 <= 3'b0;
    end else if ((sw[15] ^ previous_sw) && cs) begin // if switch 9 start sending the amount the switches count to
      pixel_ready <= 1'b1;
      pixel_to_send <= sw[7:0];
      value_to_display <= (turn_off_cipo)? 8'b0 : sw[7:0];
      rgb0 <= (rgb0 == 3'b001)? 3'b100 : 3'b001;
      rgb1 <= (sw[14])? 3'b101 : 3'b010;
    end else begin
      pixel_ready <= 1'b0;
      pixel_to_send <= 8'b0;
    end

    previous_sw <= sw[15];
  end



  /*
    SPI SENDER
  */

  logic turn_off_cipo;
  logic busy;
  assign turn_off_cipo = sw[13];
  spi_send_con #(
    .DATA_WIDTH(8),
    .LINES(4),
    .DATA_CLK_PERIOD(12)
  ) spi_send (
    .clk_in(clk_camera),
    .rst_in(sys_rst),
    .data_in(pixel_to_send),
    .trigger_in(pixel_ready),
    .hcount_in((sw[14])? 636 : 600),
    .vcount_in(356),
    .turn_off_cipo_in(turn_off_cipo),

    .final_pixel_out(tlast),
    .chip_data_out(cipo),
    .chip_clk_out(dclk),
    .chip_sel_out(cs)
  );

endmodule // top_level

`default_nettype wire