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
  input wire dclk,
  input wire cs
  );
 
  //shut up those rgb LEDs for now (active high):
  assign rgb1 = 0; //set to 0.
 
  //have btnd control system reset
  logic sys_rst;
  assign sys_rst = btn[0];
 
  logic [15:0] btn_count; //use me to keep track of counting
  assign led = btn_count;

  spi_receive_con # (
      .DATA_WIDTH(8),
      .LINES(4),
      .DATA_CLK_PERIOD(6)
    ) spi_receive (
    .clk_in(clk_100mhz),
    .rst_in(sys_rst),
    .data_out(number),
    .data_valid_out(data_valid),
    .chip_data_in(cipo),
    .chip_clk_in(dclk),
    .chip_sel_in(cs)
  );

  logic [7:0] number;
  logic data_valid;
  logic [31:0] val_to_display;
  always_ff @(posedge clk_100mhz) begin
    if (sys_rst) begin
      rgb0 <= 3'b0;
      val_to_display <= 32'b0;
    end else if (data_valid) begin
      val_to_display <= {24'b0, number};
      rgb0 <= 3'b101;
    end
  end
  // assign val_to_display = {16'b0, sw};
  logic [6:0] ss_c;
  assign ss0_c = ss_c;
  assign ss1_c = ss_c;
  seven_segment_controller mssc(.clk_in(clk_100mhz),
                               .rst_in(sys_rst),
                               .val_in(val_to_display),
                               .cat_out(ss_c),
                               .an_out({ss0_an, ss1_an}));
 
 
endmodule // top_level
 