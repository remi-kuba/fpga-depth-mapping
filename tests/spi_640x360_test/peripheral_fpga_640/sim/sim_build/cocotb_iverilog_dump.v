module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/remi/Desktop/fpga-depth-mapping/peripheral_fpga/sim/sim_build/addr_counter.fst");
    $dumpvars(0, addr_counter);
end
endmodule
