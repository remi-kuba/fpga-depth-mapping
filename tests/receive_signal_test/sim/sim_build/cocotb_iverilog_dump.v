module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/remi/Desktop/fpga-depth-mapping/receive_signal/sim/sim_build/spi_receive_con_2.fst");
    $dumpvars(0, spi_receive_con_2);
end
endmodule