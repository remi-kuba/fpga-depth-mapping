// `timescale 1ns / 1ps
`default_nettype none


module sad (
    input wire clk_in,
    input wire rst_in,
    input wire [KERNEL_SIZE-1:0][7:0] left_data_in,
    input wire [KERNEL_SIZE-1:0][7:0] right_data_in,
    input wire [10:0] hcount_in,
    input wire [9:0] vcount_in,
    input wire data_valid_in,
    output logic data_valid_out,
    output logic busy_out, // whether it is still calculating a module
    output logic [9:0] hcount_out,
    output logic [8:0] vcount_out,
    output logic [7:0] line_out
    );

    localparam KERNEL_SIZE = 3;
    localparam OFFSET_BLOCK_SIZE = OFFSET * KERNEL_SIZE;
    localparam BLOCK_SIZE = OFFSET * OFFSET;
    localparam LEFT_CACHE_SIZE = KERNEL_SIZE * KERNEL_SIZE;
    localparam RIGHT_CACHE_SIZE = (KERNEL_SIZE+OFFSET)*KERNEL_SIZE;
    localparam OFFSET = 10;

    // make cache elements 9 bits to hold a sign bit at top
    logic [LEFT_CACHE_SIZE-1:0][8:0] left_cache;
    logic [RIGHT_CACHE_SIZE-1:0][8:0] right_cache;
    logic [$clog2(OFFSET)-1:0] curr_offset;
    logic [$clog2(OFFSET)-1:0] best_offset;
    logic [$clog2(OFFSET*KERNEL_SIZE)-1:0] block_offset;
    logic [11:0] smallest_diff; // This should be unsigned

    // FOR TESTING PUPROSES
    logic [$clog2(BLOCK_SIZE)+7:0] recent_diff; // 7 for 255 color



    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            left_cache <= 0;
            right_cache <= 0;
            curr_offset <= OFFSET;
            best_offset <= OFFSET;
            smallest_diff <= ~0; 
            block_offset <= 0;
            recent_diff <= 0;
            
            data_valid_out <= 1'b0;
            busy_out <= 1'b0;
            hcount_out <= 10'b0;
            vcount_out <= 9'b0;
            line_out <= 8'b0;
        end else if (busy_out) begin
            busy_out <= (curr_offset != 0);
            curr_offset <= (curr_offset - 1 >= 0)? curr_offset - 1 : OFFSET;
            data_valid_out <= (curr_offset == 0);
            block_offset <= block_offset - KERNEL_SIZE;
    
            if (((left_cache[0] - right_cache[block_offset]) + 
                (left_cache[1] - right_cache[block_offset+1]) + 
                (left_cache[2] - right_cache[block_offset+2]) + 
                (left_cache[3] - right_cache[block_offset+3]) + 
                (left_cache[4] - right_cache[block_offset+4]) + 
                (left_cache[5] - right_cache[block_offset+5]) + 
                (left_cache[6] - right_cache[block_offset+6]) + 
                (left_cache[7] - right_cache[block_offset+7]) + 
                (left_cache[8] - right_cache[block_offset+8]) 
                ) < smallest_diff) begin
                smallest_diff <= (
                    (left_cache[0] - right_cache[block_offset]) + 
                    (left_cache[1] - right_cache[block_offset+1]) + 
                    (left_cache[2] - right_cache[block_offset+2]) + 
                    (left_cache[3] - right_cache[block_offset+3]) + 
                    (left_cache[4] - right_cache[block_offset+4]) + 
                    (left_cache[5] - right_cache[block_offset+5]) + 
                    (left_cache[6] - right_cache[block_offset+6]) + 
                    (left_cache[7] - right_cache[block_offset+7]) + 
                    (left_cache[8] - right_cache[block_offset+8]) );
                best_offset <= curr_offset;
            end
            recent_diff <= (
                (left_cache[0] - right_cache[block_offset]) + 
                (left_cache[1] - right_cache[block_offset+1]) + 
                (left_cache[2] - right_cache[block_offset+2]) + 
                (left_cache[3] - right_cache[block_offset+3]) + 
                (left_cache[4] - right_cache[block_offset+4]) + 
                (left_cache[5] - right_cache[block_offset+5]) + 
                (left_cache[6] - right_cache[block_offset+6]) + 
                (left_cache[7] - right_cache[block_offset+7]) + 
                (left_cache[8] - right_cache[block_offset+8]) );

        end else if (data_valid_in) begin
            hcount_out <= hcount_in;
            vcount_out <= vcount_in;
            busy_out <= 1'b1;
            data_valid_out <= 1'b0;

            for (int i = 0; i < LEFT_CACHE_SIZE-3; i++) begin
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

            smallest_diff <= (  (left_cache[5] - right_cache[38]) +
                                (left_cache[4] - right_cache[37]) + 
                                (left_cache[3] - right_cache[36]) +
                                (left_cache[2] - right_cache[35]) +
                                (left_cache[1] - right_cache[34]) + 
                                (left_cache[0] - right_cache[33]) +
                                ({1'b0, left_data_in[0]} - right_cache[32]) +
                                ({1'b0, left_data_in[1]} - right_cache[31]) +
                                ({1'b0, left_data_in[2]} - right_cache[30]));
            recent_diff <= (    (left_cache[5] - right_cache[38]) +
                                (left_cache[4] - right_cache[37]) + 
                                (left_cache[3] - right_cache[36]) +
                                (left_cache[2] - right_cache[35]) +
                                (left_cache[1] - right_cache[34]) + 
                                (left_cache[0] - right_cache[33]) +
                                ({1'b0, left_data_in[0]} - right_cache[32]) +
                                ({1'b0, left_data_in[1]} - right_cache[31]) +
                                ({1'b0, left_data_in[2]} - right_cache[30]));
            
            best_offset <= OFFSET;
            curr_offset <= curr_offset - 1;
            block_offset <= OFFSET_BLOCK_SIZE;
        end else data_valid_out <= 1'b0;
    end

endmodule

`default_nettype wire

