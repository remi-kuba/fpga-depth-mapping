`timescale 1ns / 1ps
`default_nettype none

/*
 * stacker
 * 
 * AXI-Stream (approximately) module that takes in serialized 16-bit messages
 * and stacks them together into 128-bit messages. Least-significant bytes
 * received first.
 */

module stacker
  (
  input wire           clk_in,
  input wire           rst_in,
  // input axis: 16 bit pixels
  input wire           pixel_tvalid,
  output logic         pixel_tready,
  // input wire [31:0]    pixel_tdata,
  input wire [7:0]    pixel_tdata,
  // input wire [15:0]    pixel_tdata,
  input wire           pixel_tlast,
  // output axis: 128 bit mig-phrases
  output logic         chunk_tvalid,
  input wire           chunk_tready,
  output logic [127:0] chunk_tdata,
  output logic         chunk_tlast
);

  logic [127:0] data_recent;
  // logic [1:0] count;
  logic [3:0]   count;
  // logic [2:0] count;
  // logic [3:0] tlast_recent;
  logic [15:0]   tlast_recent;
  // logic [7:0] tlast_recent;

  
  // start accepting when have valid pixel coming in from camera and 

  logic         accept_in;
  assign accept_in = pixel_tvalid && pixel_tready;

  // assign pixel_tready = (count == 3) ? chunk_tready : 1'b1;
  assign pixel_tready = ((count == 15) || pixel_tlast) ? chunk_tready : 1'b1;
  // assign pixel_tready = (count == 7) ? chunk_tready : 1'b1;

  logic accept_out;
  assign accept_out = chunk_tready && chunk_tvalid;
  
  always_ff @(posedge clk_in) begin
    if(rst_in) begin
      data_recent  <= 128'b0;
      count        <= 0;
      tlast_recent <= 16'b0;
      chunk_tvalid <= 1'b0;
    end else begin
      if (accept_in) begin
        // data_recent <= {pixel_tdata[31:0], data_recent[127:32]};
        data_recent  <= { pixel_tdata[7:0], data_recent[127:8] };
        // data_recent  <= { pixel_tdata[15:0], data_recent[127:16] };
        // tlast_recent <= { pixel_tlast, tlast_recent[3:1] };
        tlast_recent <= { pixel_tlast, tlast_recent[15:1] };
        // tlast_recent <= { pixel_tlast, tlast_recent[7:1] };
        count        <= (pixel_tlast)? 0 : count + 1;

        // if (count == 3) begin
        if ((count == 15) || pixel_tlast) begin
        // if (count == 7) begin
          // chunk_tdata <= {pixel_tdata[31:0], data_recent[127:32]};
          chunk_tdata  <= { pixel_tdata[7:0], data_recent[127:8] };
          // chunk_tdata  <= { pixel_tdata[15:0], data_recent[127:16] };
          chunk_tlast <= (tlast_recent[15:1] > 0) || pixel_tlast;
          // chunk_tlast <= (tlast_recent > 0);
          chunk_tvalid <= 1'b1;
        end
        
      end
      if (accept_out) begin
        chunk_tvalid <= 1'b0;
      end
    end
  end
  
endmodule

`default_nettype wire
