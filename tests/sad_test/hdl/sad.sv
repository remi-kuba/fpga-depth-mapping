`timescale 1ns / 1ps
`default_nettype none


module sad #(
    parameter KERNEL_WIDTH = 3,
    parameter OFFSET = 10
) (
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
    output logic [7:0] line_out, // relative depth
    output logic [$clog2(OFFSET)-1:0] offset_out, // FOR TESTING PURPOSES
    output logic [$clog2(KERNEL_SIZE)+7:0] diffs_out [OFFSET-1:0] // FOR TESTING PURPOSES
    );

    // TODO: RENAME PARAMS
    localparam RIGHT_OFFSET = OFFSET * KERNEL_WIDTH;
    localparam KERNEL_SIZE = KERNEL_WIDTH * KERNEL_WIDTH;
    localparam RIGHT_CACHE_SIZE = (KERNEL_WIDTH+OFFSET)*KERNEL_WIDTH;

    // make cache elements 9 bits to hold a sign bit at top
    logic [KERNEL_SIZE-1:0][7:0] left_cache;
    logic [RIGHT_CACHE_SIZE-1:0][7:0] right_cache;
    logic [$clog2(OFFSET)-1:0] curr_offset;
    logic [$clog2(OFFSET)-1:0] best_offset;
    logic [$clog2(OFFSET*KERNEL_WIDTH)-1:0] block_offset;
    logic [$clog2(KERNEL_SIZE)+7:0] smallest_diff; // This should be unsigned
    logic [9:0] hcount_pl;
    logic [8:0] vcount_pl;
    logic calc_depth;
    logic [OFFSET:0][7:0] depth;
    localparam HALF_KERNEL = KERNEL_SIZE / 2;


    
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
    logic first_half;
    logic [$clog2(KERNEL_SIZE)+7:0] first_diff;
    always_comb begin
        if (busy_out && first_half) begin
            diff = 0;
            for (int i = 0; i < KERNEL_SIZE / 2; i++) begin
                val = left_cache[i] - right_cache[i+block_offset];
                val = (val[8] == 1)? ~val + 1 : val;
                diff += val;
            end
        end else if (busy_out) begin
            diff = 0;
            for (int i = KERNEL_SIZE / 2; i < KERNEL_SIZE; i++) begin
                val = left_cache[i] - right_cache[i+block_offset];
                val = (val[8] == 1)? ~val + 1 : val;
                diff += val;
            end
        end else if (data_valid_in) begin
            diff = ~0;
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
            first_half <= 1'b1;
            first_diff <= 0;
            
            data_valid_out <= 1'b0;
            busy_out <= 1'b0;
            hcount_out <= 10'b0;
            vcount_out <= 9'b0;
            line_out <= 8'b0;
            offset_out <= 0;
        end else if (busy_out) begin
            busy_out <= (curr_offset > 0);
            calc_depth <= (curr_offset == 0);
            curr_offset <= (first_half && curr_offset > 0)? curr_offset : (curr_offset > 0)? curr_offset - 1 : OFFSET;
            block_offset <= (first_half)? block_offset : block_offset - KERNEL_WIDTH;
            first_half <= ~first_half;
            first_diff <= (first_half)? diff : 0;

            hcount_out <= hcount_pl;
            vcount_out <= vcount_pl;
    
            if (~first_half && ((first_diff + diff) <= smallest_diff)) begin
                smallest_diff <= first_diff + diff;
                best_offset <= curr_offset;
            end
            recent_diff <= diff;
            diffs_out[curr_offset] <= diff;

        end else if (data_valid_in) begin
            hcount_pl <= hcount_in;
            vcount_pl <= vcount_in;
            busy_out <= 1'b1;

            left_cache <= {left_cache[KERNEL_SIZE-4:0],left_data_in[0],left_data_in[1],left_data_in[2]};
            right_cache <= {right_cache[RIGHT_CACHE_SIZE-4:0],right_data_in[0],right_data_in[1],right_data_in[2]};

            smallest_diff <= diff;
            recent_diff <= diff;
            diffs_out[curr_offset] <= diff;
            
            best_offset <= OFFSET;
            block_offset <= RIGHT_OFFSET;
        end 

        if (calc_depth) begin
            data_valid_out <= 1'b1;
            calc_depth <= 1'b0;
            line_out <= depth[best_offset];
            offset_out <= best_offset;
        end else begin
            data_valid_out <= 1'b0;
        end
    end

endmodule

`default_nettype wire

