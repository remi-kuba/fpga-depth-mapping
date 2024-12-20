`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module top_level(
  input wire clk_100mhz, //100 MHz onboard clock
  input wire [15:0] sw, //all 16 input slide switches
  input wire [3:0] btn, //all four momentary button switches
  output logic [15:0] led, //16 green output LEDs (located right above switches)
  output logic [2:0] rgb0, //RGB channels of RGB LED0
  output logic [2:0] rgb1, //RGB channels of RGB LED1
  output logic [3:0] ss0_an,//anode control for upper four digits of seven-seg display
  output logic [3:0] ss1_an,//anode control for lower four digits of seven-seg display
  output logic [6:0] ss0_c, //cathode controls for the segments of upper four digits
  output logic [6:0] ss1_c, //cathode controls for the segments of lower four digits
  input wire [3:0] cipo,
  input wire tlast,
  input wire spi_vsync,
  input wire dclk,
  input wire cs
  );
 
  //shut up those rgb LEDs for now (active high):
  assign rgb1 = 0; //set to 0.
 
  //have btnd control system reset
  logic sys_rst;
  assign sys_rst = btn[0];
  logic clk_100_passthrough, clk_camera;
  cw_fast_clk_wiz wizard_migcam(
    .clk_in1(clk_100mhz),
    .clk_camera(clk_camera),
    .clk_100(clk_100_passthrough),
    .reset(0));
 
  // logic [15:0] btn_count; //use me to keep track of counting
  // assign led = btn_count;

    spi_receive_con_2 # (
      .DATA_WIDTH(8),
      .LINES(4)
    ) spi_receive (
    .clk_in(clk_camera),
    .rst_in(sys_rst),
    .final_pixel_in(tlast),
    .final_pixel_out(f_tlast),
    .data_out(number),
    .data_valid_out(data_valid),
    .chip_data_in(cipo),
    .chip_clk_in(dclk),
    .chip_sel_in(cs)
  );
  logic f_tlast;
  logic [7:0] number;
  logic data_valid;
  logic [31:0] val_to_display;
  always_ff @(posedge clk_camera) begin
    if (sys_rst) begin
      rgb0 <= 3'b0;
      val_to_display <= 32'hFFFF_FFFF;
    end else if (data_valid) begin
      val_to_display <= {24'b0, number};
      // green = not sw[14]
      // purple = sw[14]
      rgb0 <= (f_tlast)? 3'b101 : 3'b010;
    end
  end

  logic [6:0] ss_c;
  assign ss0_c = ss_c;
  assign ss1_c = ss_c;
  seven_segment_controller mssc(.clk_in(clk_100_passthrough),
                               .rst_in(sys_rst),
                               .val_in(val_to_display),
                               .cat_out(ss_c),
                               .an_out({ss0_an, ss1_an}));
 
 
endmodule // top_level
