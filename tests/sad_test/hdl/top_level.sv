`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module top_level(
  input wire clk_100mhz, //100 MHz onboard clock
  input wire [15:0] sw, //all 16 input slide switches
  input wire [3:0] btn, //all four momentary button switches

  // HDMI
  output logic [2:0] hdmi_tx_p, //hdmi output signals (positives) (blue, green, red)
  output logic [2:0] hdmi_tx_n, //hdmi output signals (negatives) (blue, green, red)
  output logic hdmi_clk_p, hdmi_clk_n //differential hdmi clock

  // SPI 
  output logic dclk, // data clock output of SPI controller
  output logic [5:0] cipo, // six parallel data outputs of SPI controller
  output logic cs, // chip select line for the SPI bus

  // Camera
  input wire [7:0]    camera_d, // 8 parallel data wires
  output logic        cam_xclk, // XC driving camera
  input wire          cam_hsync, // camera hsync wire
  input wire          cam_vsync, // camera vsync wire
  input wire          cam_pclk, // camera pixel clock
  inout wire          i2c_scl, // i2c inout clock
  inout wire          i2c_sda, // i2c inout data
  );

  /*
    RESETS
  */
  // btn[0] controls system reset
  logic sys_rst;
  assign sys_rst = btn[0];


  

  
endmodule // top_level
 