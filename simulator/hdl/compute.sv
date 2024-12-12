`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module compute # (
    parameter TASK_WIDTH = 16*7, 
    parameter DIMS = 2, // x, y, z
    parameter H = 16'b0_10000_000000000, // 2.0f
    parameter KERNEL_COEFF = 16'h57F4,
    parameter DIV_KERNEL_COEFF = 16'h5BF4
) (
    input wire clk_in,
    input wire rst,
    input wire valid_task,
    input wire [1:0] task_type,
    input wire [TASK_WIDTH-1:0] data_in,  // [x_i, x_j, P_i, P_j, rho_j_recip], 16*5=80
    output logic [16*DIMS-1:0] data_out,
    output logic terms_in_flight,
    output logic data_valid_out,
    // output logic [5:0] [15:0] stages_out
    // Simulation Config
    // output logic [15:0] stages
    input wire [15:0] gravitational_constant
);

    localparam ADDER_CYCLES = 4;
    localparam MULTI_CYCLES = 3 + 1;
    localparam DIV_CYCLES = 26;
    localparam SQRT_CYCLES = 12;
    localparam DISTANCE_CYCLES = 2 * ADDER_CYCLES + MULTI_CYCLES + SQRT_CYCLES;

    logic [6:0] [15:0] stages;
    // assign stages_out = stages;

    logic [16*DIMS-1:0] x_i; // position of particle i
    logic [16*DIMS-1:0] x_j; // position of particle j
    logic [16-1:0] P_i; // pressure of particle i
    logic [16-1:0] P_j; // pressure of particle j
    logic [16-1:0] rho_j_recip; // density of particle j
    logic in_density_tasks; // controls output selection

    always_ff @( posedge clk_in ) begin 
        if (valid_task) begin
            in_density_tasks <= task_type == 2'b00;
        end
    end

    assign {x_i, x_j, P_i, P_j, rho_j_recip} = data_in;

    logic [1:0] density_busy;

    // Calculate Distance
    logic [15:0] distance_result;
    logic distance_valid;
    // distance 3 -> 26
    calc_distance #(
        .DIMS(DIMS),
        .H(H)
    ) distance (
        .clk_in(clk_in),
        .rst(rst),
        .r_i(x_i),
        .r_j(x_j),
        .data_valid_in(valid_task),
        .result(distance_result),
        .busy(density_busy[0]),
        .data_valid_out(distance_valid)
    );

    always_ff @( posedge clk_in ) begin 
        if (rst) begin
            stages[0] <= 0;
        end else if (distance_valid) begin
            stages[0] <= distance_result;
        end
    end

    parameter KERNEL_CYCLES = ADDER_CYCLES + 2 * MULTI_CYCLES;
    parameter DERIV_KERNEL_CYCLES = DISTANCE_CYCLES + ADDER_CYCLES + MULTI_CYCLES;
    // Task Type 0: Calculate Density
    logic [15:0] density_result;
    logic kernel_valid;
    calc_spiky_kernel #(
        .H(H),
        .KERNEL_COEFF(KERNEL_COEFF),
        .DIV_KERNEL_COEFF(DIV_KERNEL_COEFF)
    ) kernel (
        .clk_in(clk_in),
        .rst(rst),
        .r(distance_result),
        .data_valid_in(distance_valid),
        .is_density_task(in_density_tasks), // handles both density and force
        .result(density_result),
        .data_valid_out(kernel_valid),
        .busy(density_busy[1])
    );

    // This will be 0 if r > H, and then the output will be 0
    localparam KERNEL_STAGES = DISTANCE_RECIP_CYCLES - DISTANCE_CYCLES + MULTI_CYCLES + 3;
    logic [KERNEL_STAGES-1:0] [15:0] kernel_pipe;
    logic [KERNEL_STAGES-1:0] kernel_pipe_valid;
    always_ff @( posedge clk_in ) begin 
        if (rst) begin
            kernel_pipe_valid <= 0;
            kernel_pipe <= 0;
        end else begin
            kernel_pipe <= {kernel_pipe[KERNEL_STAGES-2:0], density_result};
            kernel_pipe_valid <= {kernel_pipe_valid[KERNEL_STAGES-2:0], kernel_valid && !in_density_tasks};
        end    
    end

    // calc_kernel #(
    //     .H(H)
    // ) kernel (
    //     .clk_in(clk_in),
    //     .rst(rst),
    //     .r(distance_result),
    //     .data_valid_in(distance_valid && in_density_tasks),
    //     .result(density_result),
    //     .data_valid_out(kernel_valid),
    //     .busy(density_busy[1])
    // );

    // Task Type 1: Calculate Forces 
    // Cycles 3 -> 54, could be lowered with division optimization

    logic [2:0] force_busy;
    logic [DIMS-1:0] [5:0] inter_busy;

    logic [DIMS-1:0] [15:0] r_i_elems;
    logic [DIMS-1:0] [15:0] r_j_elems;
    
    assign r_i_elems = x_i;
    assign r_j_elems = x_j;

    logic [16-1:0] density_sum_result;
    logic density_sum_valid;
    binary16_adder density_adder (
        .clk_in(clk_in),
        .rst(rst),
        .a(P_i),
        .b(P_j), // 1.0
        .data_valid_in(valid_task && task_type == 2'b01),
        .result(density_sum_result),
        .data_valid_out(density_sum_valid),
        .busy(force_busy[0])
    );

    always_ff @( posedge clk_in ) begin 
        if (rst) begin
            stages[1] <= 0;
        end else if (density_sum_valid) begin
            stages[1] <= density_sum_result;
        end
    end

    logic [DIMS-1:0] [15:0] elem_diff_result;
    logic [DIMS-1:0] elem_diff_valid;

    logic [DIMS-1:0] [15:0] elem_multi_result;
    logic [DIMS-1:0] elem_multi_valid;

    logic [DIMS-1:0] [15:0] elem_terms_result;
    logic [DIMS-1:0] elem_terms_valid;

    logic [15:0] half_rho_result;
    logic half_rho_valid;
    // multi has inconsistent output here 
    binary16_multi half_rho (
        .clk_in(clk_in),
        .rst(rst),
        .a(rho_j_recip),
        .b(16'b1_01110_0000000000), // -0.5
        .data_valid_in(valid_task && task_type == 2'b01),
        .result(half_rho_result),
        .data_valid_out(half_rho_valid),
        .busy(force_busy[1])
    );

    always_ff @( posedge clk_in ) begin 
        if (rst) begin
            stages[2] <= 0;
        end else if (half_rho_valid) begin
            stages[2] <= half_rho_result;
        end
    end

    localparam RHO_STAGES = ADDER_CYCLES;
    logic [RHO_STAGES-1:0] [15:0] half_rho_pipe;
    logic [RHO_STAGES-1:0] half_rho_pipe_valid;
    always_ff @( posedge clk_in ) begin 
        if (rst) begin
            half_rho_pipe_valid <= 0;
            half_rho_pipe <= 0;
        end else begin
            half_rho_pipe <= {half_rho_pipe[RHO_STAGES-2:0], half_rho_result};
            half_rho_pipe_valid <= {half_rho_pipe_valid[RHO_STAGES-2:0], half_rho_valid};
        end    
    end

    generate 
        genvar i;
        for (i=0; i<DIMS; i=i+1) begin
            binary16_adder elem_diff (
                .clk_in(clk_in),
                .rst(rst),
                .a(r_i_elems[i] ^ 16'h8000), // make these reference dimensions, this makes the force vector negative
                .b(r_j_elems[i]), // flip sign bit
                .data_valid_in(valid_task && task_type == 2'b01),
                .result(elem_diff_result[i]),
                .data_valid_out(elem_diff_valid[i]),
                .busy(inter_busy[i][0])
            );
            binary16_multi elem_multiply (
                .clk_in(clk_in),
                .rst(rst),
                .a(elem_diff_result[i]),
                .b(density_sum_result), 
                .data_valid_in(elem_diff_valid[i] & density_sum_valid),
                .result(elem_multi_result[i]),
                .data_valid_out(elem_multi_valid[i]),
                .busy(inter_busy[i][1])
            );
            binary16_multi elem_terms (
                .clk_in(clk_in),
                .rst(rst),
                .a(elem_multi_result[i]),
                .b(half_rho_pipe[RHO_STAGES-1]),
                .data_valid_in(elem_multi_valid[i] & half_rho_pipe_valid[RHO_STAGES-1]),
                .result(elem_terms_result[i]),
                .data_valid_out(elem_terms_valid[i]),
                .busy(inter_busy[i][2])
            );
        end
    endgenerate

    localparam DISTANCE_RECIP_CYCLES = DISTANCE_CYCLES + DIV_CYCLES - (ADDER_CYCLES + 2 * MULTI_CYCLES);
    logic [DISTANCE_RECIP_CYCLES-1:0] [DIMS-1:0] [15:0] elem_pipe;
    logic [DISTANCE_RECIP_CYCLES-1:0] [DIMS-1:0] elem_pipe_valid;
    always_ff @( posedge clk_in ) begin 
        if (rst) begin
            elem_pipe_valid <= 0;
            elem_pipe <= 0;
        end else begin
            elem_pipe <= {elem_pipe[DISTANCE_RECIP_CYCLES-2:0], elem_terms_result};
            elem_pipe_valid <= {elem_pipe_valid[DISTANCE_RECIP_CYCLES-2:0], elem_terms_valid};
        end    
    end

    // This module doesn't release its busy signal until a cycle after the first distance completes
    // Thus, there is a gap, which needs to be closed for terms_in_flight
    logic [15:0] distance_recip_result;
    logic distance_recip_valid;
    binary16_div_pipelined distance_recip (
        .clk_in(clk_in),
        .rst(rst),
        .a(16'b0_01111_0000000000), // 1.0
        .b(distance_result),
        .data_valid_in(distance_valid & !in_density_tasks),
        .result(distance_recip_result),
        .data_valid_out(distance_recip_valid),
        .busy(force_busy[2])
    );

    always_ff @( posedge clk_in ) begin 
        if (rst) begin
            stages[3] <= 0;
        end else if (distance_recip_valid) begin
            stages[3] <= distance_recip_result;
        end
    end

    //  Calculate DeltaW(r, h), here after distance, one extra for some reason
    // logic [DIV_CYCLES-2:0] in_range_pipe;
    // always_ff @( posedge clk_in ) begin : DeltaW
    //     if (rst) begin
    //         in_range_pipe <= 0;
    //     end else begin
    //         in_range_pipe <= {in_range_pipe[DIV_CYCLES-3:0], 1'b1};
    //         if (distance_valid & !in_density_tasks) begin
    //             // r > H
    //             if ((distance_result[14:10] > H[14:10]) || ((distance_result[14:10] == H[14:10]) && (distance_result[9:0] > H[9:0]))) begin
    //                 in_range_pipe <= {in_range_pipe[DIV_CYCLES-3:0], 1'b0};
    //             end 
    //         end
    //     end 
    // end

    // if for whatever reason, dst < 0, then we can choose a random direction
    logic [DIMS-1:0] [15:0] elem_force_result, kernel_force_result, grav_sum_result;
    logic [DIMS-1:0] elem_force_valid, kernel_force_valid, grav_sum_valid;
    generate
        for (i=0; i<DIMS; i=i+1) begin
            binary16_multi elem_force (
                .clk_in(clk_in),
                .rst(rst),
                // .a((in_range_pipe[DIV_CYCLES-2]) ? distance_recip_result : 16'b0),
                .a(distance_recip_result), // this can undefined, it will get cancelled
                .b(elem_pipe[DISTANCE_RECIP_CYCLES-1][i]), // flip sign bit
                .data_valid_in(elem_pipe_valid[DISTANCE_RECIP_CYCLES-1][i] & distance_recip_valid),
                .result(elem_force_result[i]),
                .data_valid_out(elem_force_valid[i]),
                .busy(inter_busy[i][3])
            );
            binary16_multi kernel_force (
                .clk_in(clk_in),
                .rst(rst),
                .a(elem_force_result[i]),
                .b(kernel_pipe[KERNEL_STAGES-1]),
                .data_valid_in(elem_force_valid[i] && kernel_pipe_valid[KERNEL_STAGES-1]),
                .result(kernel_force_result[i]),
                .data_valid_out(kernel_force_valid[i]),
                .busy(inter_busy[i][4])
            );
            binary16_adder grav_sum (
                .clk_in(clk_in),
                .rst(rst),
                // .a((i == 0) ? gravitational_constant : 16'b0),
                .a((16'b0)),
                .b(kernel_force_result[i]),
                .data_valid_in(kernel_force_valid[i]),
                .result(grav_sum_result[i]),
                .data_valid_out(grav_sum_valid[i]),
                .busy(inter_busy[i][5])
            );
        end
    endgenerate

    always_ff @( posedge clk_in ) begin 
        if (rst) begin
            stages[4] <= 0;
        end else if (elem_pipe_valid[DISTANCE_RECIP_CYCLES-1][0] & distance_recip_valid) begin
            stages[4] <= elem_pipe[DISTANCE_RECIP_CYCLES-1][0]; // last element
        end
    end

    always_ff @( posedge clk_in ) begin 
        if (rst) begin
            stages[6:5] <= 0;
        end else if (elem_force_valid[0]) begin
            stages[6:5] <= elem_force_result; // last element
        end
    end

    always_ff @(posedge clk_in) begin 
        terms_in_flight <= |{inter_busy, force_busy, density_busy, distance_valid, elem_pipe_valid}; // stubbing
        // data_valid_out = (in_density_tasks) ? kernel_valid : &elem_force_valid;
        data_valid_out = (in_density_tasks) ? kernel_valid : &grav_sum_valid;
        // data_valid_out <= (in_density_tasks) ? kernel_valid : &kernel_force_valid;
        // data_out = (in_density_tasks) ? {16'b0, density_result} : elem_force_result;
        data_out = (in_density_tasks) ? {16'b0, density_result} : grav_sum_result;
        // data_out <= (in_density_tasks) ? {16'b0, density_result} : kernel_force_result;
    end

endmodule

`default_nettype wire