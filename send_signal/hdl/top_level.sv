`timescale 1ns / 1ps
`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module top_level(
  input wire clk_100mhz, //100 MHz onboard clock
  input wire [15:0] sw, //all 16 input slide switches
  input wire [3:0] btn, //all four momentary button switches
  output logic [15:0] led,
  output logic [2:0] rgb1,
  output logic [2:0] rgb0,

  // SPI 
  output logic dclk, // data clock output of SPI controller
  output logic [3:0] cipo, // six parallel data outputs of SPI controller
  output logic cs, // chip select line for the SPI bus
  output logic spi_hsync,
  output logic spi_vsync
  );

  // assign rgb0 = sw[2:0];
  // assign rgb1 = sw[5:3];
  /*
    RESETS
  */
  // btn[0] controls system reset
  logic sys_rst;
  assign sys_rst = btn[0];

  assign led = sw;
  assign rgb0 = 0;
  logic [7:0] pixel_to_send;
  logic pixel_ready;
  logic previous_sw;

  always_ff @(posedge clk_100mhz) begin
    if (sys_rst) begin
      pixel_ready <= 1'b0;
      pixel_to_send <= 8'b0;
      rgb1 <= 3'b0;
    end else if (sw[15] && ~previous_sw) begin // if switch 9 start sending the amount the switches count to
      pixel_ready <= 1'b1;
      pixel_to_send <= sw[7:0];
      rgb1 <= 3'b101;
    end else begin
      pixel_ready <= 1'b0;
      pixel_to_send <= 8'b0;
    end

    previous_sw <= sw[15];
  end

  /*
    SPI SENDER
  */
  spi_send_con #(
    .DATA_WIDTH(8),
    .LINES(4),
    .DATA_CLK_PERIOD(6)
  ) spi_send (
    .clk_in(clk_100mhz),
    .rst_in(sys_rst),
    .data_in(pixel_to_send),
    .trigger_in(pixel_ready),

    .chip_data_out(cipo),
    .chip_clk_out(dclk),
    .chip_sel_out(cs)
  );

endmodule // top_level

`default_nettype wire