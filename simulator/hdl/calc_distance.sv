`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module calc_distance #(
   parameter DIMS = 2, // x, y, z
   parameter H = 16'h4400 // 16'b0_01111_0000000000 // 1.0
) (
    input wire clk_in,
    input wire rst,
    input wire [16*DIMS-1:0] r_i,
    input wire [16*DIMS-1:0] r_j,
    input wire data_valid_in,
    output logic [15:0] result,
    output logic data_valid_out,
    output logic busy
);

    // TODO: Fix the undefined signals in beginning bug

    // Fully pipelined
    // result = |r_i - r_j|

    logic [DIMS-1:0] [15:0] elem_diff_result;
    logic [DIMS-1:0] elem_diff_valid;
    logic [DIMS-1:0] [15:0] elem_diff_sq_result;
    logic [DIMS-1:0] elem_diff_sq_valid;

    logic [1:0] busy_signal;
    logic [DIMS-1:0] [1:0] inter_busy;

    logic [DIMS-1:0] [15:0] r_i_elems;
    logic [DIMS-1:0] [15:0] r_j_elems;
    
    assign r_i_elems = r_i;
    assign r_j_elems = r_j;

    generate 
        genvar i;
        for (i=0; i<DIMS; i=i+1) begin
            binary16_adder elem_diff (
                .clk_in(clk_in),
                .rst(rst),
                .a(r_i_elems[i]), // make these reference dimensions
                .b(r_j_elems[i] ^ 16'h8000), // flip sign bit
                .data_valid_in(data_valid_in),
                .result(elem_diff_result[i]),
                .data_valid_out(elem_diff_valid[i]),
                .busy(inter_busy[i][0])
            );
            binary16_multi elem_diff_sq (
                .clk_in(clk_in),
                .rst(rst),
                .a(elem_diff_result[i]),
                .b(elem_diff_result[i]),
                .data_valid_in(elem_diff_valid[i]),
                .result(elem_diff_sq_result[i]),
                .data_valid_out(elem_diff_sq_valid[i]),
                .busy(inter_busy[i][1])
            );
        end
    endgenerate

    logic [15:0] sq_distance;
    logic sq_distance_valid;
    binary16_adder sq_distance_adder (
        .clk_in(clk_in),
        .rst(rst),
        .a(elem_diff_sq_result[0]),
        .b(elem_diff_sq_result[1]),
        .data_valid_in(elem_diff_sq_valid[0] & elem_diff_sq_valid[1]), // should both be valid at the same time
        .result(sq_distance),
        .data_valid_out(sq_distance_valid),
        .busy(busy_signal[0])
    );
    
    logic [15:0] distance;
    logic distance_valid;
    binary16_sqrt sqrt (
        .clk_in(clk_in),
        .rst(rst),
        .n(sq_distance),
        // .n(elem_diff_sq_result),
        .data_valid_in(sq_distance_valid),
        // .data_valid_in(elem_diff_sq_valid),
        .result(distance),
        .data_valid_out(distance_valid),
        .busy(busy_signal[1])
    );

    assign busy = |(busy_signal | inter_busy);
    assign result = distance;
    assign data_valid_out = distance_valid;

endmodule

`default_nettype wire