module counters (
    input wire clk_in,
    input wire rst_in,
    output logic [8:0] hcount_out,
    output logic [8:0] vcount_out
    );
    localparam FB_DEPTH = 10*8;
    localparam FB_SIZE = $clog2(FB_DEPTH);

    logic [FB_SIZE-1:0] addrb;
    assign hcount_out = hcount_spi[3];
    assign vcount_out = vcount_spi[3];
    logic [3:0] [7:0] hcount_spi;
    logic [3:0] [7:0] vcount_spi;
    // logic [2:0] good_addrb;
    always_ff @(posedge clk_in) begin
        addrb <= hcount_spi[0] + (vcount_spi[0] * 10);
        hcount_spi[1] <= hcount_spi[0];
        hcount_spi[2] <= hcount_spi[1];
        hcount_spi[3] <= hcount_spi[2];
        vcount_spi[1] <= vcount_spi[0];
        vcount_spi[2] <= vcount_spi[1];
        vcount_spi[3] <= vcount_spi[2];
    end
    logic read_request;
    logic trigger;
    bram_counter #(
    .MAX_COUNT(12) // data clock period * 2 
    ) bc (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .hit_max_out(trigger),
    .read_request_out(read_request)
    );
    evt_counter #(
        .MAX_COUNT(10)
    ) hcounter (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .evt_in(read_request),
        .count_out(hcount_spi[0])
    );

    evt_counter #(
        .MAX_COUNT(8)
    ) vcounter (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .evt_in(read_request && hcount_spi[0] == 9),
        .count_out(vcount_spi[0])
    );
    // addr_counter # (
    // .HCOUNT(10),
    // .VCOUNT(8)
    // ) increment_hvcount (
    // .clk_in(clk_in),
    // .rst_in(rst_in),
    // .evt_in(read_request),
    // .hcount_out(hcount_spi[0]),
    // .vcount_out(vcount_spi[0])
    // );

endmodule