`timescale 1ns / 1ps
`default_nettype none


module signed_math(
    input wire clk_in,
    input wire rst_in,
    // input wire [4:0] a_in,
    // input wire [4:0] b_in,
    input wire [2:0][7:0] left_in,
    input wire [2:0][7:0] right_in,
    input wire data_valid_in,
    output logic [4:0] something_out,
    output logic [11:0] diff_out
);

    logic busy;
    logic [8:0][7:0] left_cache;
    logic [8:0][7:0] right_cache;
    logic [11:0] diff;
    logic [8:0] val;
    logic [5:0] c;
    logic [5:0] d;
    always_comb begin
        if (data_valid_in) begin
            diff = 0;
            for (int i = 0; i < 6; i++) begin
                val = left_cache[i] - right_cache[i];
                val = (val[8] == 1)? ~val + 1 : val;
                diff += val;
            end

            val = {1'b0, left_in[0]} - {1'b0, right_in[0]};
            val = (val[8] == 1)? ~val + 1 : val;
            diff += val;
            val = {1'b0, left_in[1]} - {1'b0, right_in[1]};
            val = (val[8] == 1)? ~val + 1 : val;
            diff += val;
            val = {1'b0, left_in[2]} - {1'b0, right_in[2]};
            val = (val[8] == 1)? ~val + 1 : val;
            diff += val;

        end else diff = 0;
    end

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            c <= 6'b0;
            d <= 6'b0;
            something_out <= 5'b0;
            busy <= 1'b0;
            diff_out <= 12'b0;
            left_cache <= 0;
            right_cache <= 0;
        end else begin 
            if (data_valid_in) begin
                diff_out <= diff;

                for (int i = 0; i < 3; i++) begin
                    left_cache[i] <= left_in[2-i];
                    right_cache[i] <= right_in[2-i];
                end

                for (int i = 0; i < 6; i++) begin
                    left_cache[i+3] <= left_cache[i];
                    right_cache[i+3] <= right_cache[i]; 
                end
            end

            // c <= a_in - b_in;
            // d <= {1'b0, a_in} - {1'b0, b_in};
            // something_out <= (d[5] == 1)? ~d + 1 : d;
        end
    end


endmodule
`default_nettype wire