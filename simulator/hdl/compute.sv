`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module compute # (
    parameter DATA_WIDTH = 16,
    parameter H = 16'b0_01111_0000000000
) (
    input wire clk_in,
    input wire rst,
    input wire valid_task,
    input wire [1:0] task_type,
    input wire [DATA_WIDTH*5-1:0] data_in,  // [x_i, x_j, P_i, P_j, rho_j], 16*5=80
    output logic [15:0] data_out,
    output logic terms_in_flight,
    output logic data_valid_out
);

    // Task Type 0: Calculate Density
    calc_density #(
        .DIMS(1),
        .PARTICLE_COUNTER_SIZE(2),
        .H(H)
    ) density (
        .clk_in(clk_in),
        .rst(rst),
        .r_i(data_in[79:64]),
        .r_j(data_in[63:48]),
        .data_valid_in(valid_task && task_type == 2'b00),
        .result(data_out),
        .busy(terms_in_flight),
        .data_valid_out(data_valid_out)
    );

    // Task Type 1: Calculate Forces
    

endmodule

`default_nettype wire