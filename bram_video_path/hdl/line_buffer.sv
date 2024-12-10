`default_nettype none

module line_buffer (
            input wire clk_in, //system clock
            input wire rst_in, //system reset

            input wire [10:0] hcount_in, //current hcount being read
            input wire [9:0] vcount_in, //current vcount being read
            input wire [7:0] pixel_data_in, //incoming pixel
            input wire data_valid_in, //incoming  valid data signal

            output logic [KERNEL_SIZE-1:0][7:0] line_buffer_out, //output pixels of data
            output logic [10:0] hcount_out, //current hcount being read
            output logic [9:0] vcount_out, //current vcount being read
            output logic data_valid_out //valid data out signal
  );
  parameter HRES = 320;
  parameter VRES = 160;
  localparam KERNEL_SIZE = 3;

  logic [KERNEL_SIZE:0][7:0] read_data; // read bram every cycle
  logic [1:0][10:0] hcount_pl;
  logic [1:0][9:0] vcount_pl;
  logic [1:0] data_valid_pl;
  logic [2:0][1:0] write_to_pl;

  always_ff @(posedge clk_in) begin
    if (rst_in) begin
      for (int i = 0; i < KERNEL_SIZE; i = i + 1) begin
        line_buffer_out[i] <= 16'b0;
        write_to_pl[i] <= 2'b0;
      end 
      data_valid_out <= 1'b0;
      hcount_out <= 11'b0;
      vcount_out <= 10'b0;
      data_valid_pl <= 2'b0;
      for (int i = 0; i < 2; i = i + 1) begin
        hcount_pl[i] <= 11'b0;
        vcount_pl[i] <= 10'b0;
      end
    end else begin
      // if data is valid
        // insert that into the data_valid_pl
      data_valid_pl <= {data_valid_pl[0], data_valid_in};

      hcount_pl[0] <= hcount_in;
      vcount_pl[0] <= (vcount_in - 2 >= 0)? vcount_in - 2 :
                      vcount_in - 2 + VRES; 

      hcount_pl[1] <= hcount_pl[0];
      vcount_pl[1] <= vcount_pl[0];
      
      // induces the two cycle delay
      hcount_out <= hcount_pl[1];
      vcount_out <= vcount_pl[1];
      data_valid_out <= data_valid_pl[1];

      write_to_pl[0] <= (data_valid_in && hcount_in == HRES - 1)? 
                          ((vcount_in == VRES - 1)? 0 : write_to_pl[0] + 1) :
                        write_to_pl[0];
      write_to_pl[1] <= write_to_pl[0];
      write_to_pl[2] <= write_to_pl[1];

      if (data_valid_pl[1]) begin // should return the received pixels
        case (write_to_pl[2]) // which buffers correspond to which
          0: line_buffer_out[2:0] <= read_data[3:1];
          1: line_buffer_out[2:0] <= {read_data[0], read_data[3:2]};
          2: line_buffer_out[2:0] <= {read_data[1:0], read_data[3]};
          default: line_buffer_out[2:0] <= read_data[2:0];
        endcase
      end
    end 
  end

  generate
    genvar i;
    for (i = 0; i < 4; i = i + 1) begin
      xilinx_true_dual_port_read_first_1_clock_ram #(
        .RAM_WIDTH(16),
        .RAM_DEPTH(HRES),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE")) line_buffer_ram (
        .clka(clk_in),     // Clock
        //writing port:
        .addra(hcount_in),   // Port A address bus,
        .dina(pixel_data_in),     // Port A RAM input data
        .wea(data_valid_in && write_to_pl[0] == i),       // Port A write enable
        //reading port:
        .addrb(hcount_in),   // Port B address bus,
        .doutb(read_data[i]),    // Port B RAM output data,
        .douta(),   // Port A RAM output data, width determined from RAM_WIDTH
        .dinb(0),     // Port B RAM input data, width determined from RAM_WIDTH
        .web(1'b0),       // Port B write enable
        .ena(1'b1),       // Port A RAM Enable
        .enb(1'b1),       // Port B RAM Enable,
        .rsta(1'b0),     // Port A output reset
        .rstb(1'b0),     // Port B output reset
        .regcea(1'b1), // Port A output register enable
        .regceb(1'b1) // Port B output register enable
      );
    end
  endgenerate
endmodule


`default_nettype wire

