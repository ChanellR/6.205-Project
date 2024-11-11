module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/isaactaylor/VSCodeProjects/6205Project/render/sim_build/painter.fst");
    $dumpvars(0, painter);
end
endmodule
