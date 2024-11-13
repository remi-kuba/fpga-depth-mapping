`default_nettype none
module center_of_mass (
                         input wire clk_in,
                         input wire rst_in,
                         input wire [10:0] x_in,
                         input wire [9:0]  y_in,
                         input wire valid_in,
                         input wire tabulate_in,
                         output logic [10:0] x_out,
                         output logic [9:0] y_out,
                         output logic valid_out);
	 // your code here
     localparam WIDTH = 29;
     logic [WIDTH-1:0] x_tot; // log_2(768*sum(0-1023))
     logic [WIDTH-1:0] y_tot; // log_2(1024*sum(0-767))
     logic [WIDTH-1:0] m_tot; // log_2(1024 * 768) ~ 20
     logic [WIDTH-1:0] x_quot, y_quot;
     logic x_done, y_done; 
     logic x_error, y_error;
     logic x_busy, y_busy;
    //  logic half_ready;
     logic data_valid_in;
     assign data_valid_in = tabulate_in && (m_tot > 0);

     divider #(.WIDTH(WIDTH)) 
     x_calc (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .dividend_in(x_tot),
        .divisor_in(m_tot),
        .data_valid_in(data_valid_in),
        .quotient_out(x_quot),
        .remainder_out(),
        .data_valid_out(x_done),
        .error_out(x_error),
        .busy_out(x_busy));

    divider #(.WIDTH(WIDTH)) 
     y_calc (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .dividend_in(y_tot),
        .divisor_in(m_tot),
        .data_valid_in(data_valid_in),
        .quotient_out(y_quot),
        .remainder_out(),
        .data_valid_out(y_done),
        .error_out(y_error),
        .busy_out(y_busy));

     always_ff @(posedge clk_in) begin
        if (rst_in) begin
            x_tot <= 20'b0;
            y_tot <= 20'b0;
            m_tot <= 20'b0;
            x_out <= 11'b0;
            y_out <= 10'b0;
            // half_ready <= 1'b0;
            valid_out <= 1'b0;
        end else if (valid_in) begin
            x_tot <= x_tot + x_in;
            y_tot <= y_tot + y_in;
            m_tot <= m_tot + 1'b1;
        end 

        x_out <= (x_done && !x_error)? x_quot[10:0] : x_out;
        y_out <= (y_done && !y_error)? y_quot[9:0] : y_out;
        if ((x_done && !x_error && !y_busy) || 
            (y_done && !y_error && !x_busy)) begin
            valid_out <= 1'b1;
            x_tot <= 20'b0;
            y_tot <= 20'b0;
            m_tot <= 20'b0;
        end else valid_out <= 1'b0;

        // valid_out <= (x_done && !x_error && !y_busy) || 
        //              (y_done && !y_error && !x_busy);
        // if ((x_done && !x_error) || (y_done && !y_error)) begin
        //     valid_out <= 
        // end
        // if (x_done && !x_error && y_done && !y_error) begin
        //     x_out <= x_quot[10:0];
        //     y_out <= y_quot[9:0];
        //     valid_out <= 1'b1;
        //     x_tot <= 20'b0;
        //     y_tot <= 20'b0;
        //     m_tot <= 20'b0;
        // end else if (x_done && !x_error) begin
        //     x_out <= x_quot[10:0];
        //     valid_out <= half_ready;
        //     half_ready <= ~half_ready;
        //     x_tot <= (half_ready)? 20'b0 : x_tot;
        //     y_tot <= (half_ready)? 20'b0 : y_tot;
        //     m_tot <= (half_ready)? 20'b0 : m_tot;
        // end else if (y_done && !y_error) begin
        //     y_out <= y_quot[9:0];
        //     valid_out <= half_ready;
        //     half_ready <= ~half_ready;
        //     x_tot <= (half_ready)? 20'b0 : x_tot;
        //     y_tot <= (half_ready)? 20'b0 : y_tot;
        //     m_tot <= (half_ready)? 20'b0 : m_tot;
        // end else valid_out <= 1'b0;
        
     end

endmodule

`default_nettype wire
