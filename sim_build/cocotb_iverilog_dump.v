module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/isaactaylor/VSCodeProjects/6205Project/6.205-Project/sim_build/top_level_parallel.fst");
    $dumpvars(0, top_level_parallel);
end
endmodule
