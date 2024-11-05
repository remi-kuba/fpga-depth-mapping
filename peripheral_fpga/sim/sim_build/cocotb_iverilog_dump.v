module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/remi/Desktop/fpga-depth-mapping/peripheral_fpga/sim/sim_build/spi_send_con.fst");
    $dumpvars(0, spi_send_con);
end
endmodule
