module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/isaactaylor/VSCodeProjects/6205Project/6.205-Project/simulator/sim_build/top_level.fst");
    $dumpvars(0, top_level);
end
endmodule
