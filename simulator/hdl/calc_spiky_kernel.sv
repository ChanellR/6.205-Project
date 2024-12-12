`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module calc_spiky_kernel #(
   parameter H = 16'h359A, // 0.35f
   parameter KERNEL_COEFF =  16'h57F4, // 6 / (PI * H^4)
   parameter DIV_KERNEL_COEFF = 16'h5BF4 // 12 / (PI * H^4)
) (
    input wire clk_in,
    input wire rst,
    input wire [16-1:0] r, // scalar distance between p_i and p_j
    input wire data_valid_in,
    input wire is_density_task,
    output logic [16-1:0] result,
    output logic data_valid_out,
    output logic busy
);

    // module takes 12/16 cycles to complete

    // Fully pipelined
    // result = m_j * W(r, h)
    // W(r, h) = (r - H)^2 * coeff
    logic [15:0] div = DIV_KERNEL_COEFF;
    logic [3:0] busy_parts;
    logic [15:0] diff_result, diff_sq_result, coeff_result, deriv_coeff_result;
    logic diff_valid, diff_sq_valid, coeff_valid, deriv_coeff_valid;
    binary16_adder diff (
        .clk_in(clk_in),
        .rst(rst),
        .a(H[15:0] | 16'h8000), // H - r
        .b(r), // force subtraction
        .data_valid_in(data_valid_in),
        .result(diff_result),
        .data_valid_out(diff_valid),
        .busy(busy_parts[0])
    );
    // derivative skipping
    binary16_multi deriv_coeff (
        .clk_in(clk_in),
        .rst(rst),
        .a((diff_result[15]) ? diff_result ^ 16'h8000 : 16'b0), // negate
        .b(DIV_KERNEL_COEFF & 16'hFFFF),
        .data_valid_in(diff_valid && !is_density_task),
        .result(deriv_coeff_result),
        .data_valid_out(deriv_coeff_valid),
        .busy(busy_parts[1])
    );
    binary16_multi diff_sq (
        .clk_in(clk_in),
        .rst(rst),
        .a((diff_result[15]) ? diff_result : 16'h0),
        .b((diff_result[15]) ? diff_result : 16'h0),
        .data_valid_in(diff_valid && is_density_task),
        .result(diff_sq_result),
        .data_valid_out(diff_sq_valid),
        .busy(busy_parts[2])
    );
    binary16_multi coeff (
        .clk_in(clk_in),
        .rst(rst),
        .a(diff_sq_result),
        .b(KERNEL_COEFF & 16'hFFFF),
        .data_valid_in(diff_sq_valid),
        .result(coeff_result),
        .data_valid_out(coeff_valid),
        .busy(busy_parts[3])
    );

    assign busy = |busy_parts;
    assign result = (is_density_task) ? coeff_result : deriv_coeff_result;
    assign data_valid_out = (is_density_task) ? coeff_valid : deriv_coeff_valid;

endmodule

`default_nettype wire