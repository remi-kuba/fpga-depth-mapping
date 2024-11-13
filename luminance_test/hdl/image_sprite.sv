`timescale 1ns / 1ps
`default_nettype none

`ifdef SYNTHESIS
`define FPATH(X) `"X`"
`else /* ! SYNTHESIS */
`define FPATH(X) `"../../data/X`"
`endif  /* ! SYNTHESIS */

module image_sprite #(
  parameter WIDTH=256, HEIGHT=256) (
  input wire pixel_clk_in,
  input wire rst_in,
  input wire [10:0] x_in, hcount_in,
  input wire [9:0]  y_in, vcount_in,
  output logic [7:0] red_out,
  output logic [7:0] green_out,
  output logic [7:0] blue_out
  );

  // calculate rom address
  logic [$clog2(WIDTH*HEIGHT)-1:0] image_addr;
  assign image_addr = (hcount_in - x_in) + ((vcount_in - y_in) * WIDTH);

  logic [7:0] palette_color;
  logic[23:0] color;

  xilinx_single_port_ram_read_first #(
    .RAM_WIDTH(8),                       
    .RAM_DEPTH(WIDTH * HEIGHT),  // 256 x 256                   
    .RAM_PERFORMANCE("HIGH_PERFORMANCE"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
    .INIT_FILE(`FPATH(image.mem))         
  ) image_brom (
    .addra(image_addr),     // Address bus, width determined from RAM_DEPTH
    .dina(1'b0),       // RAM input data, width determined from RAM_WIDTH
    .clka(pixel_clk_in),       // Clock
    .wea(1'b0),         // Write enable
    .ena(1'b1),         // RAM Enable, for additional power savings, disable port when not in use
    .rsta(rst_in),       // Output reset (does not affect memory contents)
    .regcea(1'b1),   // Output register enable
    .douta(palette_color)      // RAM output data, width determined from RAM_WIDTH
  );

  xilinx_single_port_ram_read_first #(
    .RAM_WIDTH(24),                       
    .RAM_DEPTH(256),                   
    .RAM_PERFORMANCE("HIGH_PERFORMANCE"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
    .INIT_FILE(`FPATH(palette.mem))         
  ) palette_brom (
    .addra(palette_color),     // Address bus, width determined from RAM_DEPTH
    .dina(1'b0),       // RAM input data, width determined from RAM_WIDTH
    .clka(pixel_clk_in),       // Clock
    .wea(1'b0),         // Write enable
    .ena(1'b1),         // RAM Enable, for additional power savings, disable port when not in use
    .rsta(rst_in),       // Output reset (does not affect memory contents)
    .regcea(1'b1),   // Output register enable
    .douta(color)      // RAM output data, width determined from RAM_WIDTH
  );


  logic in_sprite [3:0];
  always_ff @(posedge pixel_clk_in) begin
    in_sprite[0] <= ((hcount_in >= x_in && hcount_in < (x_in + WIDTH)) &&
                      (vcount_in >= y_in && vcount_in < (y_in + HEIGHT)));
    for (integer i = 1; i < 4; i = i + 1) begin
      in_sprite[i] <= in_sprite[i - 1];
    end

    red_out <= in_sprite[3]? color[23:16] : 0;
    green_out =  in_sprite[3] ? color[15:8] : 0;
    blue_out =   in_sprite[3] ? color[7:0] : 0;
  end
endmodule


module image_sprite_2 #(
  parameter WIDTH=256, HEIGHT=256) (
  input wire pixel_clk_in,
  input wire rst_in,
  input wire pop_in, // high = top image, low = bottom image
  input wire [10:0] x_in, hcount_in,
  input wire [9:0]  y_in, vcount_in,
  output logic [7:0] red_out,
  output logic [7:0] green_out,
  output logic [7:0] blue_out
  );

  // calculate rom address
  logic [$clog2(WIDTH*HEIGHT)-1:0] image_addr;
  assign image_addr = (hcount_in - x_in) + ((vcount_in - y_in) * WIDTH) 
                      + (pop_in? 0 : WIDTH * HEIGHT); // offset by entire image pixel size to get bottom image

  logic [7:0] palette_color;
  logic[23:0] color;

  xilinx_single_port_ram_read_first #(
    .RAM_WIDTH(8),                       
    .RAM_DEPTH(WIDTH * HEIGHT),                 
    .RAM_PERFORMANCE("HIGH_PERFORMANCE"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
    .INIT_FILE(`FPATH(image.mem))         
  ) image_brom (
    .addra(image_addr),     // Address bus, width determined from RAM_DEPTH
    .dina(1'b0),       // RAM input data, width determined from RAM_WIDTH
    .clka(pixel_clk_in),       // Clock
    .wea(1'b0),         // Write enable
    .ena(1'b0),         // RAM Enable, for additional power savings, disable port when not in use
    .rsta(rst_in),       // Output reset (does not affect memory contents)
    .regcea(1'b0),   // Output register enable
    .douta(palette_color)      // RAM output data, width determined from RAM_WIDTH
  );

  xilinx_single_port_ram_read_first #(
    .RAM_WIDTH(24),                       
    .RAM_DEPTH(256),                   
    .RAM_PERFORMANCE("HIGH_PERFORMANCE"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
    .INIT_FILE(`FPATH(palette.mem))         
  ) palette_brom (
    .addra(palette_color),     // Address bus, width determined from RAM_DEPTH
    .dina(1'b0),       // RAM input data, width determined from RAM_WIDTH
    .clka(pixel_clk_in),       // Clock
    .wea(1'b0),         // Write enable
    .ena(1'b0),         // RAM Enable, for additional power savings, disable port when not in use
    .rsta(rst_in),       // Output reset (does not affect memory contents)
    .regcea(1'b0),   // Output register enable
    .douta(color)      // RAM output data, width determined from RAM_WIDTH
  );


  logic in_sprite;
  assign in_sprite = ((hcount_in >= x_in && hcount_in < (x_in + WIDTH)) &&
                      (vcount_in >= y_in && vcount_in < (y_in + HEIGHT)));

  assign red_out =    in_sprite ? color[23:16] : 0;
  assign green_out =  in_sprite ? color[15:8] : 0;
  assign blue_out =   in_sprite ? color[7:0] : 0;
endmodule




`default_nettype none
