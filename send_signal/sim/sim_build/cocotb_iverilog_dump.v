module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/remi/Desktop/fpga-depth-mapping/send_signal/sim/sim_build/spi_send_con.fst");
    $dumpvars(0, spi_send_con);
end
endmodule
