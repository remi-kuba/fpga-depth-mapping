module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/remi/Desktop/fpga-depth-mapping/controller_fpga/sim/sim_build/sad.fst");
    $dumpvars(0, sad);
end
endmodule
