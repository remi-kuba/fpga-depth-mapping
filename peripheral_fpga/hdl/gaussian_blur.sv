`timescale 1ns / 1ps
`default_nettype none


module gaussian_blur (
    input wire clk_in,
    input wire rst_in,
    input wire [KERNEL_SIZE-1:0][15:0] data_in,
    input wire [10:0] hcount_in,
    input wire [9:0] vcount_in,
    input wire data_valid_in,
    output logic data_valid_out,
    output logic [10:0] hcount_out,
    output logic [9:0] vcount_out,
    output logic [15:0] line_out
    );

    localparam KERNEL_SIZE = 3;
    logic [8:0][15:0] cache;
    logic [1:0] processing;
    logic signed [8:0][15:0] proc_cache_r;
    logic signed [8:0][15:0] proc_cache_g;
    logic signed [8:0][15:0] proc_cache_b;
    logic [1:0] [10:0] proc_hcount;
    logic [1:0] [9:0] proc_vcount;
    
    logic signed [20:0] r_sum;
    logic signed [20:0] g_sum;
    logic signed [20:0] b_sum;

    logic signed [7:0] shift;
    logic signed [2:0][2:0][7:0] coeffs;


    always_comb begin
        coeffs[0][0] = rst_in ? 8'sd0 : 8'sd1;
        coeffs[0][1] = rst_in ? 8'sd0 : 8'sd2;
        coeffs[0][2] = rst_in ? 8'sd0 : 8'sd1;
        coeffs[1][0] = rst_in ? 8'sd0 : 8'sd2;
        coeffs[1][1] = rst_in ? 8'sd0 : 8'sd4;
        coeffs[1][2] = rst_in ? 8'sd0 : 8'sd2;
        coeffs[2][0] = rst_in ? 8'sd0 : 8'sd1;
        coeffs[2][1] = rst_in ? 8'sd0 : 8'sd2;
        coeffs[2][2] = rst_in ? 8'sd0 : 8'sd1;
        shift = rst_in ? 8'sd0 : 8'sd4;
    end

        
    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            processing <= 2'b0;
            for (int i = 0; i < 9; i++) begin
                cache[i] <= 16'b0;
                proc_cache_r[i] <= 16'sb0;
                proc_cache_g[i] <= 16'sb0;
                proc_cache_b[i] <= 16'sb0;
            end
            for (int i = 0; i < 2; i++) begin
                proc_hcount[i] <= 11'b0;
                proc_vcount[i] <= 10'b0;
            end
            r_sum <= 16'sb0;
            g_sum <= 16'sb0;
            b_sum <= 16'sb0;
            hcount_out <= 11'b0;
            vcount_out <= 10'b0;
            line_out <= 16'b0;
            data_valid_out <= 1'b0;
        end else begin
            if (data_valid_in) begin // Multiplication stage
                processing[0] <= 1'b1;
                proc_hcount[0] <= hcount_in;
                proc_vcount[0] <= vcount_in;

                for (int i = 0; i < 6; i++) begin
                    cache[i + 3] <= cache[i];
                end
                cache[2] <= data_in[0];
                cache[1] <= data_in[1];
                cache[0] <= data_in[2];

                proc_cache_r[8] <= $signed({3'b0, cache[5][15:11]}) * $signed(coeffs[2][2]);
                proc_cache_r[7] <= $signed({3'b0, cache[4][15:11]}) * $signed(coeffs[1][2]);
                proc_cache_r[6] <= $signed({3'b0, cache[3][15:11]}) * $signed(coeffs[0][2]);
                proc_cache_r[5] <= $signed({3'b0, cache[2][15:11]}) * $signed(coeffs[2][1]);
                proc_cache_r[4] <= $signed({3'b0, cache[1][15:11]}) * $signed(coeffs[1][1]);
                proc_cache_r[3] <= $signed({3'b0, cache[0][15:11]}) * $signed(coeffs[0][1]);
                proc_cache_r[2] <= $signed({3'b0, data_in[0][15:11]}) * $signed(coeffs[2][0]);
                proc_cache_r[1] <= $signed({3'b0, data_in[1][15:11]}) * $signed(coeffs[1][0]);
                proc_cache_r[0] <= $signed({3'b0, data_in[2][15:11]}) * $signed(coeffs[0][0]);

                proc_cache_g[8] <= $signed({2'b0, cache[5][10:5]}) * $signed(coeffs[2][2]);
                proc_cache_g[7] <= $signed({2'b0, cache[4][10:5]}) * $signed(coeffs[1][2]);
                proc_cache_g[6] <= $signed({2'b0, cache[3][10:5]}) * $signed(coeffs[0][2]);
                proc_cache_g[5] <= $signed({2'b0, cache[2][10:5]}) * $signed(coeffs[2][1]);
                proc_cache_g[4] <= $signed({2'b0, cache[1][10:5]}) * $signed(coeffs[1][1]);
                proc_cache_g[3] <= $signed({2'b0, cache[0][10:5]}) * $signed(coeffs[0][1]);
                proc_cache_g[2] <= $signed({2'b0, data_in[0][10:5]}) * $signed(coeffs[2][0]);
                proc_cache_g[1] <= $signed({2'b0, data_in[1][10:5]}) * $signed(coeffs[1][0]);
                proc_cache_g[0] <= $signed({2'b0, data_in[2][10:5]}) * $signed(coeffs[0][0]);

                proc_cache_b[8] <= $signed({3'b0, cache[5][4:0]}) * $signed(coeffs[2][2]);
                proc_cache_b[7] <= $signed({3'b0, cache[4][4:0]}) * $signed(coeffs[1][2]);
                proc_cache_b[6] <= $signed({3'b0, cache[3][4:0]}) * $signed(coeffs[0][2]);
                proc_cache_b[5] <= $signed({3'b0, cache[2][4:0]}) * $signed(coeffs[2][1]);
                proc_cache_b[4] <= $signed({3'b0, cache[1][4:0]}) * $signed(coeffs[1][1]);
                proc_cache_b[3] <= $signed({3'b0, cache[0][4:0]}) * $signed(coeffs[0][1]);
                proc_cache_b[2] <= $signed({3'b0, data_in[0][4:0]}) * $signed(coeffs[2][0]);
                proc_cache_b[1] <= $signed({3'b0, data_in[1][4:0]}) * $signed(coeffs[1][0]);
                proc_cache_b[0] <= $signed({3'b0, data_in[2][4:0]}) * $signed(coeffs[0][0]);
            end else processing[0] <= 1'b0;

            if (processing[0]) begin
                processing[1] <= 1'b1;
                proc_hcount[1] <= proc_hcount[0];
                proc_vcount[1] <= proc_vcount[0];

                r_sum <= ($signed(proc_cache_r[0]) + $signed(proc_cache_r[1]) + $signed(proc_cache_r[2]) + 
                            $signed(proc_cache_r[3]) + $signed(proc_cache_r[4]) + $signed(proc_cache_r[5]) + 
                            $signed(proc_cache_r[6]) + $signed(proc_cache_r[7]) + $signed(proc_cache_r[8])) >>> shift;
                g_sum <= ($signed(proc_cache_g[0]) + $signed(proc_cache_g[1]) + $signed(proc_cache_g[2]) + 
                            $signed(proc_cache_g[3]) + $signed(proc_cache_g[4]) + $signed(proc_cache_g[5]) + 
                            $signed(proc_cache_g[6]) + $signed(proc_cache_g[7]) + $signed(proc_cache_g[8])) >>> shift;
                b_sum <= ($signed(proc_cache_b[0]) + $signed(proc_cache_b[1]) + $signed(proc_cache_b[2]) + 
                            $signed(proc_cache_b[3]) + $signed(proc_cache_b[4]) + $signed(proc_cache_b[5]) + 
                            $signed(proc_cache_b[6]) + $signed(proc_cache_b[7]) + $signed(proc_cache_b[8])) >>> shift;
            end else processing[1] <= 1'b0;
            
            if (processing[1]) begin
                data_valid_out <= 1'b1;
                hcount_out <= proc_hcount[1];
                vcount_out <= proc_vcount[1];

                line_out[15:11] <= (r_sum < 21'sb0)? 5'b0 :
                                    (r_sum > 21'sh1F)? 5'h1F : r_sum[4:0];
                line_out[10:5] <= (g_sum < 21'sb0)? 6'b0 :
                                    (g_sum > 21'sh3F)? 6'h3F : g_sum[5:0];
                line_out[4:0] <= (b_sum < 21'sb0)? 5'b0 :
                                    (b_sum > 21'sh1F)? 5'h1F : b_sum[4:0];
            end else data_valid_out <= 1'b0;
        end
    end
endmodule

`default_nettype wire

