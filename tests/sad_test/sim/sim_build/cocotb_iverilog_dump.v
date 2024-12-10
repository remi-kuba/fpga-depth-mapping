module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/remi/Desktop/something/fpga-depth-mapping/tests/sad_test/sim/sim_build/sad.fst");
    $dumpvars(0, sad);
end
endmodule
