module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/isaactaylor/VSCodeProjects/6205Project/6.205-Project/sim_build/render.fst");
    $dumpvars(0, render);
end
endmodule
