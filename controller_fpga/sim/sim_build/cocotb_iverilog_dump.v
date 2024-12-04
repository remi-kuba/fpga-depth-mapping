module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/veloriapannell/Downloads/6.205/fpga-depth-mapping/controller_fpga/sim/sim_build/traffic_generator.fst");
    $dumpvars(0, traffic_generator);
end
endmodule
