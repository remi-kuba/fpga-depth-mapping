module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/remi/Desktop/lab05_partb/sim/sim_build/pixel_reconstruct.fst");
    $dumpvars(0, pixel_reconstruct);
end
endmodule
