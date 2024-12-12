`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module calc_density #(
   parameter DIMS = 1, // x, y, z
   parameter PARTICLE_COUNTER_SIZE = 2,
   parameter H = 16'h4400 // 16'b0_01111_0000000000 // 1.0
) (
    input wire clk_in,
    input wire rst,
    input wire [15:0] r_i,
    input wire [15:0] r_j,
    input wire data_valid_in,
    output logic [15:0] result,
    output logic data_valid_out,
    output logic busy
);

    // Fully pipelined
    // result = m_j * W(r, h)
    // W(r, h) = max(0, h - r)
    // r = ((r_i - r_j)^2)^(1/2)

    logic [15:0] elem_diff_result;
    logic elem_diff_valid;
    logic [15:0] elem_diff_sq_result;
    logic elem_diff_sq_valid;

    logic [3:0] busy_signal;

    binary16_adder elem_diff (
        .clk_in(clk_in),
        .rst(rst),
        .a(r_i), // make these reference dimensions
        .b(r_j ^ 16'H8000), // flip sign bit
        .data_valid_in(data_valid_in),
        .result(elem_diff_result),
        .data_valid_out(elem_diff_valid),
        .busy(busy_signal[0])
    );

    binary16_multi elem_diff_sq (
        .clk_in(clk_in),
        .rst(rst),
        .a(elem_diff_result),
        .b(elem_diff_result),
        .data_valid_in(elem_diff_valid),
        .result(elem_diff_sq_result),
        .data_valid_out(elem_diff_sq_valid),
        .busy(busy_signal[1])
    );


    // generate 
    //     genvar i;
    //     for (i=0; i<DIMS; i=i+1) begin
    //         binary16_adder elem_diff (
    //             .clk_in(clk_in),
    //             .rst(rst),
    //             .a(r_i), // make these reference dimensions
    //             .b(r_j ^ (1 << 15)),
    //             .data_valid_in(data_valid_in),
    //             .result(elem_diff_result[i]),
    //             .data_valid_out(elem_diff_valid[i]),
    //             .busy()
    //         );
    //         binary16_multi elem_diff_sq (
    //             .clk_in(clk_in),
    //             .rst(rst),
    //             .a(elem_diff_result[i]),
    //             .b(elem_diff_result[i]),
    //             .data_valid_in(elem_diff_valid[i]),
    //             .result(elem_diff_sq_result[i]),
    //             .data_valid_out(elem_diff_sq_valid[i])
    //         );
    //     end
    // endgenerate

    logic [15:0] sq_distance;
    logic sq_distance_valid;
    // binary16_adder sq_distance_adder (
    //     .clk_in(clk_in),
    //     .rst(rst),
    //     .a(elem_diff_sq_result[0]),
    //     .b(elem_diff_sq_result[1]),
    //     .data_valid_in(elem_diff_sq_valid[0] & elem_diff_sq_valid[1]), // should both be valid at the same time
    //     .result(sq_distance),
    //     .data_valid_out(sq_distance_valid),
    //     .busy(busy_signal[2])
    // );
    
    logic [15:0] distance;
    logic distance_valid;
    binary16_sqrt sqrt (
        .clk_in(clk_in),
        .rst(rst),
        // .n(sq_distance),
        .n(elem_diff_sq_result),
        // .data_valid_in(sq_distance_valid),
        .data_valid_in(elem_diff_sq_valid),
        .result(distance),
        .data_valid_out(distance_valid),
        .busy(busy_signal[2])
    );

    logic [15:0] result_store;
    logic result_valid;
    binary16_adder result_adder (
        .clk_in(clk_in),
        .rst(rst),
        .a(H), // 1.0 - H
        .b(distance | 16'h8000), // force subtraction
        .data_valid_in(distance_valid),
        .result(result_store),
        .data_valid_out(result_valid),
        .busy(busy_signal[3])
    );

    assign busy = |busy_signal;

    always_ff @( posedge clk_in ) begin
        if (rst) begin
            data_valid_out <= 0;
        end else begin
            // max(0, h - r)
            result <= (result_store & (1 << 15)) ? 16'h0 : result_store;
            data_valid_out <= result_valid;
        end
    end


endmodule

`default_nettype wire