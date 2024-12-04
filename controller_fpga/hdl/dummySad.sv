

// `timescale 1ns / 1ps
`default_nettype none

//dummySad module to just spit out average of the two pixels
module dummySad (
    input wire clk_in,
    input wire rst_in,
    input wire [KERNEL_WIDTH-1:0][7:0] left_data_in,
    input wire [KERNEL_WIDTH-1:0][7:0] right_data_in,
    input wire [10:0] hcount_in,
    input wire [9:0] vcount_in,
    input wire data_valid_in,
    output logic data_valid_out,
    output logic busy_out, // whether it is still calculating a module
    output logic [9:0] hcount_out,
    output logic [8:0] vcount_out,
    output logic [7:0] line_out // relative depth
    );

    // TODO: RENAME PARAMS
    localparam KERNEL_WIDTH = 3;
    localparam RIGHT_OFFSET = OFFSET * KERNEL_WIDTH;
    localparam KERNEL_SIZE = KERNEL_WIDTH * KERNEL_WIDTH;
    localparam RIGHT_CACHE_SIZE = (KERNEL_WIDTH+OFFSET)*KERNEL_WIDTH;
    localparam OFFSET = 10;

    // make cache elements 9 bits to hold a sign bit at top
    logic [KERNEL_SIZE-1:0][8:0] left_cache;
    logic [RIGHT_CACHE_SIZE-1:0][8:0] right_cache;
    logic [$clog2(OFFSET)-1:0] curr_offset;
    logic [$clog2(OFFSET)-1:0] best_offset;
    logic [$clog2(OFFSET*KERNEL_WIDTH)-1:0] block_offset;
    logic [$clog2(KERNEL_SIZE)+7:0] smallest_diff; // This should be unsigned
    logic [9:0] hcount_pl;
    logic [8:0] vcount_pl;
    logic calc_depth;
    logic [OFFSET:0][7:0] depth;
    
    // relative depth: 255 / OFFSET * best_offset
    assign depth = {
        8'd255,
        8'd229,
        8'd204,
        8'd178,
        8'd153,
        8'd127,
        8'd102,
        8'd76,
        8'd51,
        8'd25,
        8'd0};

    // FOR TESTING PUPROSES
    logic [$clog2(KERNEL_SIZE)+7:0] recent_diff; // 7 for 255 color

    logic [$clog2(KERNEL_SIZE)+7:0] diff;
    logic [8:0] val; // calculate a single |left[x][y] - right[x+offset][y]|
    always_comb begin
        if (busy_out) begin
            diff = 0;
            for (int i = 0; i < KERNEL_SIZE; i++) begin
                // val = (left_cache[i] - right_cache[block_offset + i]);
                val = (left_cache[i] + right_cache[i]); //just add the two
                
                // diff += (val[8] == 1)? ~val + 1 : val; //if <0, adj w/signed flip
                diff += (val[8] == 1)? ~(val>>1) + 1 : val>>1;
            end
        end else if (data_valid_in) begin
            diff = 0;
            for (int i = 0; i < KERNEL_SIZE - KERNEL_WIDTH; i++) begin
                // val = left_cache[i] - right_cache[i + RIGHT_OFFSET + KERNEL_WIDTH];
                val = (left_cache[i] + right_cache[i]); //just add the two

                //div by 2 to complete average of pixels
                diff += (val[8] == 1)? ~(val>>1) + 1 : val>>1;
            end

            val = ({1'b0, left_data_in[0]} - right_cache[32]);
            diff += (val[8] == 1)? ~val + 1 : val;
            val = ({1'b0, left_data_in[1]} - right_cache[31]);
            diff += (val[8] == 1)? ~val + 1 : val;
            val = ({1'b0, left_data_in[2]} - right_cache[30]);
            diff += (val[8] == 1)? ~val + 1 : val;
        end else begin
            val = 9'b0;
            diff = 0;
        end
    end

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            left_cache <= 0;
            right_cache <= 0;
            curr_offset <= OFFSET;
            best_offset <= OFFSET;
            smallest_diff <= ~0; 
            block_offset <= 0;
            recent_diff <= 0;
            calc_depth <= 1'b0;
            hcount_pl <= 10'b0;
            vcount_pl <= 9'b0;
            
            data_valid_out <= 1'b0;
            busy_out <= 1'b0;
            hcount_out <= 10'b0;
            vcount_out <= 9'b0;
            line_out <= 8'b0;
        end else if (busy_out) begin
            busy_out <= (curr_offset > 0);
            calc_depth <= (curr_offset == 0);
            curr_offset <= (curr_offset > 0)? curr_offset - 1 : OFFSET;
            block_offset <= block_offset - KERNEL_WIDTH;

            hcount_out <= hcount_pl;
            vcount_out <= vcount_pl;
    
            if (diff <= smallest_diff) begin
                smallest_diff <= diff;
                best_offset <= curr_offset;
            end
            recent_diff <= diff;

        end else if (data_valid_in) begin
            hcount_pl <= hcount_in;
            vcount_pl <= vcount_in;
            busy_out <= 1'b1;

            for (int i = 0; i < KERNEL_SIZE-3; i++) begin
                left_cache[i+3] <= left_cache[i];
            end
            for (int i = 0; i < RIGHT_CACHE_SIZE-3; i++) begin
                right_cache[i+3] <= right_cache[i];
            end
            left_cache[2] <= {1'b0, left_data_in[0]};
            left_cache[1] <= {1'b0, left_data_in[1]};
            left_cache[0] <= {1'b0, left_data_in[2]};
            right_cache[2] <= {1'b0, right_data_in[0]};
            right_cache[1] <= {1'b0, right_data_in[1]};
            right_cache[0] <= {1'b0, right_data_in[2]};

            smallest_diff <= diff;
            recent_diff <= diff;
            
            best_offset <= OFFSET;
            curr_offset <= curr_offset - 1;
            block_offset <= RIGHT_OFFSET;
        end 

        if (calc_depth) begin
            data_valid_out <= 1'b1;
            calc_depth <= 1'b0;
            line_out <= diff;
        end else begin
            data_valid_out <= 1'b0;
        end
    end

endmodule

`default_nettype wire

