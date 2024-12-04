`timescale 1ns / 1ps
`default_nettype none

/*
 * traffic_generator
 * 
 * Module to provide the memory interface IP with the signals it needs,
 * decides what commands are issued in what order. Arbitrates between
 * write requests issued by write_axis, and read requests cycling through
 * the 720p frame buffer, whose responses are fed into read_axis.
 * 
 * We've provided the state machine that manages the arbitration between
 * these requests, and the connections to each AXI-Stream. Your job is
 * to determine the address needed for each read and write request, likely
 * using some evt_counters!
 */

module traffic_generator
  (
   input wire           clk_in,      // should be ui clk of DDR3!
   input wire           rst_in,
  
   // MIG UI --> generic outputs
   output logic [26:0]  app_addr,
   output logic [2:0]   app_cmd,
   output logic         app_en,
   // MIG UI --> write outputs
   output logic [127:0] app_wdf_data,
   output logic         app_wdf_end,
   output logic         app_wdf_wren,
   output logic [15:0]  app_wdf_mask,
   // MIG UI --> read inputs
   input wire [127:0]   app_rd_data,
   input wire           app_rd_data_end,
   input wire           app_rd_data_valid,
   // MIG UI --> generic inputs
   input wire           app_rdy,
   input wire           app_wdf_rdy,
   // MIG UI --> misc
   output logic         app_sr_req,  // ??
   output logic         app_ref_req, // ??
   output logic         app_zq_req,  // ??
   input wire           app_sr_active,
   input wire           app_ref_ack,
   input wire           app_zq_ack,
   input wire           init_calib_complete,
  
   // Write SAD AXIS FIFO input
   input wire [127:0]   wr_sad_axis_data, // Change where the data is going
   input wire           wr_sad_axis_tlast,
   input wire           wr_sad_axis_valid,
   input wire           wr_sad_axis_smallpile,
   output logic         wr_sad_axis_ready,
   // Read HDMI AXIS FIFO output
   output logic [127:0] r_hdmi_axis_data,// Change where the data is going
   output logic         r_hdmi_axis_tlast,
   output logic         r_hdmi_axis_valid,
   input wire           r_hdmi_axis_af, // almost full signal
   input wire           r_hdmi_axis_ready,

   // Write Cam1 AXIS FIFO input
   input wire [127:0]   wr_cam1_axis_data, // Change where the data is going
   input wire           wr_cam1_axis_tlast,
   input wire           wr_cam1_axis_valid,
   input wire           wr_cam1_axis_smallpile,
   output logic         wr_cam1_axis_ready,
   // Read Cam1 AXIS FIFO output
   output logic [127:0] r_cam1_axis_data,// Change where the data is going
   output logic         r_cam1_axis_tlast,
   output logic         r_cam1_axis_valid,
   input wire           r_cam1_axis_af, // almost full signal
   input wire           r_cam1_axis_ready,

   // Write Cam2 AXIS FIFO input
   input wire [127:0]   wr_cam2_axis_data, // Change where the data is going
   input wire           wr_cam2_axis_tlast,
   input wire           wr_cam2_axis_valid,
   input wire           wr_cam2_axis_smallpile,
   output logic         wr_cam2_axis_ready,
   // Read Cam2 AXIS FIFO output
   output logic [127:0] r_cam2_axis_data,// Change where the data is going
   output logic         r_cam2_axis_tlast,
   output logic         r_cam2_axis_valid,
   input wire           r_cam2_axis_af, // almost full signal
   input wire           r_cam2_axis_ready

   );

  // signals needed for app_cmd, specified by documentation
  localparam CMD_WRITE = 3'b000;
  localparam CMD_READ = 3'b001;
  // unused MIG signals tied to 0
  assign app_sr_req = 0;
  assign app_ref_req = 0;
  assign app_zq_req = 0;
  assign app_wdf_mask = 16'b0;

  // state machine used to alternate between read & write requests
  typedef enum {
    RST,
		WAIT_INIT,
		RD_HDMI,
    RD_CAM1,
    RD_CAM2,
		WR_CAM1,
    WR_CAM2,
    WR_SAD
	} tg_state;
  tg_state state;

  //placeholder variables to input/output to/from different FIFOs
   // Write AXIS FIFO input
   logic [127:0]   write_axis_data;
   logic           write_axis_tlast;
   logic           write_axis_valid;
   logic           write_axis_smallpile;
   logic         write_axis_ready;
   // Read AXIS FIFO output
   logic [127:0] read_axis_data;
   logic         read_axis_tlast;
   logic         read_axis_valid;
   logic           read_axis_af; // almost full signal
   logic           read_axis_ready;

  
  // Define ready/valid signals to output to our input+output AXI Streams!
  
  // give the write FIFO a "ready" signal when the MI is ready and our state machine
  // indicates it's the write AXIS' turn.
  logic   wdf_ready;
  assign wdf_ready = app_rdy && app_wdf_rdy;
  //if wdf_ready && in a writing state
  assign write_axis_ready = wdf_ready && (state == WR_CAM1 || state == WR_CAM2 || state == WR_SAD);

  // Feed the read output from the MIG (app_rd_data and app_rd_data_valid)
  // * the MIG does not handle back-pressure--there's no hook-up for a ready signal here!
  //   so the state machine we provide you ensures that the FIFO /always/ has space available.
  //   it utilizes the "almost full" signal (read_axis_af) which goes high if there are
  //   less than 12 slots remaining in the FIFO.
  assign read_axis_valid = app_rd_data_valid;
  assign read_axis_data = app_rd_data;

  // Not an AXI-Stream, but the signals that define when we actually issue a read request.
  
  logic read_request_valid; // defined further below, based on state machine + address info
  logic read_request_ready;
  //if app_rdy && in a reading state
  assign read_request_ready = app_rdy && (state == RD_HDMI ||state == RD_CAM1 || state == RD_CAM2);

  logic write_count_in;
  logic request_count_in;
  logic read_count_in;
  logic write_rst_in;

  assign write_count_in = write_axis_ready && write_axis_valid; //handshake
  assign request_count_in = read_request_ready && read_request_valid; //handshake
  assign read_count_in = read_axis_ready && read_axis_valid; //handshake
  assign write_rst_in = (write_count_in && write_axis_tlast) || rst_in; //handshake and tlast

  evt_counter #(.MAX_COUNT(MAX_ADDR)) write_counter
    ( .clk_in(clk_in), .rst_in(write_rst_in),
      .evt_in(write_count_in),.count_out(write_address) );
  evt_counter #(.MAX_COUNT(MAX_ADDR)) request_counter
    ( .clk_in(clk_in), .rst_in(rst_in),
      .evt_in(request_count_in),.count_out(read_request_address) );
  evt_counter #(.MAX_COUNT(MAX_ADDR)) read_counter
    ( .clk_in(clk_in), .rst_in(rst_in),
      .evt_in(read_count_in),.count_out(read_response_address) );


  // TODO: define the addresses associated with each read or write command+response!
  logic [26:0] write_address;
  logic [26:0] read_request_address;
  logic [26:0] read_response_address;

  // for defining the write requests: your event should be a handshake on the write AXIStream,
  //     and the address should **reset** if a valid write axis transaction carries a TLAST !
  // for defining the read RESPONSES: your event should be a handshake on the read AXIStream
  // for defining the read REQUESTS: your event should be a "handshake" on the read requests
  
  localparam MAX_ADDR = 3*14400; // change me!!
  
  // TODO: TLAST generation for the read output!
  // assign a tlast value based on the address your response is up to!

  assign read_axis_tlast = read_response_address == MAX_ADDR; // change me!!
    

  // parameter to control how many sequential reads we'll send in a burst.
  localparam MAX_CMD_QUEUE = 16; //16 total seq req
  logic [26:0] addr_diff;
  assign addr_diff = read_request_address - read_response_address;
  assign read_request_valid = (addr_diff < MAX_CMD_QUEUE) && ~read_axis_af && (state == RD_HDMI || state == RD_CAM1 || state == RD_CAM2);

  // switch between read/write logic:
  // * if the write fifo is empty, switch to read mode
  // * if more than MAX_CMD_QUEUE requests are waiting, switch to write mode
  // * if the read data FIFO is almost full, switch to write mode
  // this state machine could be improved greatly to increase throughput on our DRAM data bus!
  logic 	go_to_wr, go_to_rd;
  assign go_to_wr = (addr_diff >= MAX_CMD_QUEUE) || read_axis_af;
  assign go_to_rd = ~write_axis_valid;
  

    // state machine used to alternate between read & write requests
  /*
  0. reset or init
  1. write cam1 data
  2. read cam1 data
  3. write cam2 data
  4. read cam2 data
  5. write from SAD (or direct to DRAM?)
  6. read DRAM output to HDMI
  */
  always_ff @(posedge clk_in) begin
    if(rst_in) begin
	    state <= RST;
    end else begin
	    case(state)
	      RST: begin
	        state <= WAIT_INIT;
	      end
	      WAIT_INIT: begin
	        state <= init_calib_complete ? RD_CAM1 : WAIT_INIT;
	      end
	      RD_CAM1: begin
	        state <= go_to_wr ? WR_CAM1 : RD_CAM1;
	      end
	      WR_CAM1: begin
	        state <= go_to_rd ? RD_CAM2 : WR_CAM1; 
	      end
	      RD_CAM2: begin
	        state <= go_to_wr  ? WR_CAM2 : RD_CAM2;
	      end
	      WR_CAM2: begin
	        state <= go_to_rd ? RD_HDMI : WR_CAM2;
	      end
	      RD_HDMI: begin
	        state <= go_to_wr ? WR_SAD : RD_HDMI;
	      end
	      WR_SAD: begin
	        state <= go_to_rd ? RD_CAM1 : WR_SAD;
	      end
	    endcase // case (state)
    end
  end

  // signals to issue to the MIG in each state: when in each state, attempt to issue commands!
  always_comb begin
    case(state)
	    RST, WAIT_INIT: begin
	      app_addr = 0;
	      app_cmd = 0;
	      app_en = 0;
	      app_wdf_data = 0;
	      app_wdf_end = 0;
	      app_wdf_wren = 0;
	    end
	    WR_CAM1, WR_CAM2, WR_SAD: begin
        // App address shifted right! !! your write_address should address a 128-bit message.
	      app_addr     = write_address << 3; 
	      app_cmd      = CMD_WRITE;
        // set command enable signals whenever the axi-stream has data valid and the MIG is ready
	      app_en       = write_axis_valid && wdf_ready;
	      app_wdf_wren = write_axis_valid && wdf_ready;
	      app_wdf_data = write_axis_data;
	      app_wdf_end  = write_axis_valid && wdf_ready;

        //Depending on state,  give different inputs
        write_axis_data = (state == WR_CAM1) ?  wr_cam1_axis_data:  (state == WR_CAM2) ? wr_cam2_axis_data : wr_sad_axis_data;
        write_axis_valid = (state == WR_CAM1) ? wr_cam1_axis_valid :  (state == WR_CAM2) ? wr_cam2_axis_valid : wr_sad_axis_valid; 
        write_axis_smallpile = (state == WR_CAM1) ? wr_cam1_axis_smallpile : (state == WR_CAM2) ? wr_cam2_axis_smallpile : wr_sad_axis_smallpile;
        write_axis_tlast = (state == WR_CAM1) ? wr_cam1_axis_tlast :  (state == WR_CAM2) ? wr_cam2_axis_tlast :  wr_sad_axis_tlast;

        //Change outputs based on state
        wr_cam1_axis_ready = (state == WR_CAM1) ?  write_axis_ready:  (state == WR_CAM2) ?  0 :  0;
        wr_cam2_axis_ready = (state == WR_CAM1) ? 0 : (state == WR_CAM2) ?  write_axis_ready : 0;
        wr_sad_axis_ready = (state == WR_CAM1) ? 0 : (state == WR_CAM2) ? 0 : write_axis_ready;

	    end
	    RD_CAM1, RD_CAM2, RD_HDMI: begin
        // App address shifted right! !! your read_request_address should address a 128-bit message.
	      app_addr = read_request_address << 3; 
	      app_cmd = CMD_READ;
	      // app_en = 1'b1;
	      app_en = read_request_valid;
	      app_wdf_wren = 1'b0;
	      app_wdf_data = 0;
	      app_wdf_end = 1'b0;

        //Depending on state,  give different inputs
        read_axis_af = (state == RD_CAM1) ? r_cam1_axis_af : (state == RD_CAM2) ? r_cam2_axis_af : r_hdmi_axis_af;
        read_axis_ready = (state == RD_CAM1) ? r_cam1_axis_ready : (state == RD_CAM2) ? r_cam2_axis_ready : r_hdmi_axis_ready;

        //Change outputs based on state
        r_cam1_axis_data = (state == RD_CAM1) ? read_axis_data : (state == RD_CAM2) ? 0 : 0; 
        r_cam2_axis_data = (state == RD_CAM1) ? 0 : (state == RD_CAM2) ? read_axis_data : 0; 
        r_hdmi_axis_data = (state == RD_CAM1) ? 0 : (state == RD_CAM2) ? 0 : read_axis_data; 
        
        r_cam1_axis_tlast = (state == RD_CAM1) ? read_axis_tlast : (state == RD_CAM2) ? 0 : 0; 
        r_cam2_axis_tlast = (state == RD_CAM1) ? 0 : (state == RD_CAM2) ? read_axis_tlast : 0; 
        r_hdmi_axis_tlast = (state == RD_CAM1) ? 0 : (state == RD_CAM2) ? 0 : read_axis_tlast; 

        r_cam1_axis_valid = (state == RD_CAM1) ? read_axis_valid : (state == RD_CAM2) ? 0 : 0; 
        r_cam2_axis_valid = (state == RD_CAM1) ? 0 : (state == RD_CAM2) ? read_axis_valid : 0; 
        r_hdmi_axis_valid = (state == RD_CAM1) ? 0 : (state == RD_CAM2) ? 0 : read_axis_valid; 


	    end
      default: begin
        app_addr     = 0;
        app_cmd      = 0;
        app_en       = 0;
        app_wdf_data = 0;
        app_wdf_end  = 0;
        app_wdf_wren = 0;
      end
    endcase // case (state)
  end // always_comb

endmodule

`default_nettype wire
