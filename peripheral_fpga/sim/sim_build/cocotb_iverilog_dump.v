module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/remi/Desktop/fpga-depth-mapping/peripheral_fpga/sim/sim_build/spi_send_con_2.fst");
    $dumpvars(0, spi_send_con_2);
end
endmodule
