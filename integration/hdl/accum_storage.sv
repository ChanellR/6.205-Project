`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module accum_storage #(
    // parameter PARTICLE_COUNT = 4,
    parameter COUNTER_SIZE = 16,
    parameter MAX_QUEUE_SIZE = 3,
    parameter DIMS = 2
    // parameter TARGET_DENSITY = 16'b0_10000_0000000000 // 2.0
    // parameter PRESSURE_CONST = 16'b0_01111_0000000000 // 1.0
) (
    input wire clk_in,
    input wire rst,
    // scheduler signals
    input wire is_density_task,
    input wire next_sum, // currently not used
    input wire [COUNTER_SIZE-1:0] main_index,
    input wire [COUNTER_SIZE-1:0] req_index,
    output logic [15:0] density_reciprocal,
    output logic [15:0] pressure,
    output logic done_accumulating,
    // receiver signals
    input wire [16*DIMS-1:0] data_in, // density: [(16*(DIMS-1))'b0, rho_i_term], force [f_i_x_term, f_i_y_term]
    input wire data_valid_in,
    input wire terms_in_flight, // this can be used to know when to stop
    // updater signals
    output logic [16*(DIMS+1)-1:0] data_out, // [sum_x, sum_y, density_reciprocal]
    output logic data_valid_out, // this can also go to the scheduler, to let it know that it is done
    input wire [15:0] pressure_const,
    input wire [15:0] target_density
);

    /* This modules function:
    * receives floats that are sent kept in a queue and then
    * paired to be added together. It will continue to add terms
    * together until the queue is empty, and it receives and ending signal.
    * It will then right the result to a specific memory location, based on
    * the main particle index.  
    * An addition takes 6 cycles, but it is fully pipelined, so it can be written to constantly.
    */

    /* Accumulation Portion */
    logic [DIMS-1:0] [16-1:0] input_terms;  // density: [16'b0, rho_i_term], force [f_i_x_term, f_i_y_term]
    assign input_terms = {data_in};

    logic [DIMS-1:0] [16-1:0] accumulator_out;
    logic [DIMS-1:0] accumulator_data_valid;
    // logic [DIMS-1:0] done_accumulating;
    
    generate
        genvar i;
        for (i=0; i<DIMS; i=i+1) begin 
            elem_accumulator #(
                // .PARTICLE_COUNT(PARTICLE_COUNT),
                .MAX_QUEUE_SIZE(MAX_QUEUE_SIZE)
            ) melem_accum (
                .clk_in(clk_in),
                .rst(rst),
                // scheduler
                // .done_accumulating(done_accumulating[i]),
                // receiver
                .data_in(input_terms[i]),
                // only activate higher dimensions when not in density task
                .data_valid_in(data_valid_in && (i == 0 || !is_density_task)), 
                .terms_in_flight(terms_in_flight),
                // updater
                .data_out(accumulator_out[i]),
                .data_valid_out(accumulator_data_valid[i])
            );
        end 
    endgenerate

    /* Density_reciprocal and Pressure Calculation Portion */
    
    logic [COUNTER_SIZE-1:0] working_index;
    
    logic [15:0] reciprocal_out;
    logic reciprocal_valid, reciprocal_done;
    binary16_div mrecip_div (
        .clk_in(clk_in),
        .rst(rst),
        .a(16'b0_01111_0000000000), // 1.0
        .b(accumulator_out[0]),
        .data_valid_in(accumulator_data_valid[0] && is_density_task),
        .result(reciprocal_out),
        .data_valid_out(reciprocal_valid)
    );

    // TODO: instead of outputting 0's like it should, it outputs -0.0078125
    // because only one term with the particle itself gives 1.9921875.
    // so, we can just clip this to 0 if it is really necessary
    logic [15:0] density_diff_out;
    logic density_diff_valid;
    binary16_adder mdensity_diff (
        .clk_in(clk_in),
        .rst(rst),
        .a(accumulator_out[0]),
        .b(target_density[15:0] | 16'h8000), // density - target_density
        .data_valid_in(accumulator_data_valid[0] && is_density_task),
        .result(density_diff_out),
        .data_valid_out(density_diff_valid)
    );


    logic pressure_valid, pressure_done;
    logic [15:0] pressure_out;
    binary16_multi mpressure_mul (
        .clk_in(clk_in),
        .rst(rst),
        .a(density_diff_out),
        .b(pressure_const), // 1.0
        .data_valid_in(density_diff_valid),
        .result(pressure_out),
        .data_valid_out(pressure_valid)
    );


    /* Storage Portion */
    // Make this BRAM
    // logic [PARTICLE_COUNT-1:0] [15:0] density_reciprocals, pressures;
    // logic [15:0] pressure_pipe, density_reciprocal_pipe;

    // Don't know how big this BRAM is actually 
    // pressure and density reciprocal take different amounts of time, so they can be combined here. 
    // all wires are 16 bits wide
    // I need to read from both ports in order to get both properties when necessary. 
    xilinx_true_dual_port_read_first_2_clock_ram  #(
        .RAM_WIDTH(16),
        .RAM_DEPTH(128) // max number of particles
    ) property_storage (
    // blk_mem_gen_0 property_storage (
        // density reciprocal
        // different if you are requesting or storing
        .addra((is_density_task || outputting) ? (main_index << 1) | 1'b0 : (req_index << 1) | 1'b0),
        // .addra(1'b1),
        .clka(clk_in),
        .wea(reciprocal_valid),
        // .wea(1'b1),
        .dina(reciprocal_out),
        // .dina(16'hFFFF),
        .ena(1'b1),
        .douta(density_reciprocal),
        .rsta(1'b0),
        .regcea(1'b1),
        // pressure
        .addrb((is_density_task) ? (main_index << 1) | 1'b1 : (req_index << 1) | 1'b1),
        .clkb(clk_in),
        .web(pressure_valid),
        .dinb(pressure_out),
        .enb(1'b1),
        .doutb(pressure),
        .rstb(1'b0),
        .regceb(1'b1)
    );

    logic [1:0] outputting;
    logic [DIMS-1:0] [15:0] to_output_accumulation;
    always_ff @(posedge clk_in) begin
        if (rst) begin
            working_index <= 0;
            done_accumulating <= 0;
            // density_reciprocals <= 0;
            // density_reciprocal_pipe <= 0;
            // pressures <= 0;
            // pressure_pipe <= 0;
            data_out <= 0;
            data_valid_out <= 0;
            outputting <= 0;
            to_output_accumulation <= 0;
        end else begin
            data_valid_out <= 0;
            done_accumulating <= 0;
            if (|accumulator_data_valid) begin // if any of the accumulators are done
                if (is_density_task) begin // store properties
                    working_index <= main_index;
                    // density_reciprocals[main_index] <= accumulator_out[0]; // perhaps these calcs in another module before the updater
                    // pressures[main_index] <= accumulator_out[0];
                    reciprocal_done <= 0;
                    pressure_done <= 0;
                end else begin
                    outputting <= 1;
                    // data_out <= {accumulator_out, density_reciprocals[main_index]};
                    to_output_accumulation <= accumulator_out;
                    // data_out <= {accumulator_out, density_reciprocals[main_index]};
                    // data_valid_out <= 1;
                    // done_accumulating <= 1;
                end
                // done_accumulating <= 1;
            end else begin
                // done_accumulating <= 0;
            end

            if (reciprocal_valid) begin
                // density_reciprocals[working_index] <= reciprocal_out;
                reciprocal_done <= 1;
            end else if (pressure_valid) begin
                // pressures[working_index] <= pressure_out;
                pressure_done <= 1;
            end else begin
                // turn off writing 
            end

            // This makes it take much longer to finish
            if (reciprocal_done && pressure_done) begin
                done_accumulating <= 1;
                reciprocal_done <= 0;
                pressure_done <= 0;
            end 

            if (outputting) begin
                outputting <= outputting + 1;
                if (outputting == 3) begin
                    data_out <= {to_output_accumulation, density_reciprocal};
                    data_valid_out <= 1;
                    done_accumulating <= 1;
                    outputting <= 0;
                end
                // data_out <= {accumulator_out, density_reciprocals[main_index]};
            end

            // scheduler data requests
            // density_reciprocal_pipe <= density_reciprocals[req_index];
            // density_reciprocal <= density_reciprocal_pipe;
            // pressure_pipe <= pressures[req_index];
            // pressure <= pressure_pipe;
        end
    end

endmodule

`default_nettype wire
