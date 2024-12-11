`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module scheduler #(
    // parameter particle_count = 4,
    parameter DIMS = 2, // x, y, z
    parameter ADDR_WIDTH = 4,                     // Specify RAM depth (number of entries)
    parameter RAM_WIDTH = 16 * 2,                       // Specify RAM data width
    parameter TASK_WIDTH = 16*5, 
    parameter COUNTER_SIZE = 16,
    parameter PREDICTION_FACTOR = 16'h1FF0, // 1 / 60.0
    parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE" // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"

) (
    input wire clk_in,
    input wire rst_in,
    output logic done, // signals the end of the frame
    // rendering
    output logic reading_positions, // signals the reading of positions
    // memory
    input wire new_frame,
    input wire [RAM_WIDTH-1:0] mem_in,
    output logic [ADDR_WIDTH-1:0] addr_out, 
    output logic mem_write_enable,
    output logic mem_enable,
    // accumulation & storage
    input wire [16-1:0] density_reciprocal,
    input wire [16-1:0] pressure,
    input wire done_accumulating,
    output logic is_density_task,
    output logic next_sum, // signals the accumulation of a new sum
    output logic [COUNTER_SIZE-1:0] req_index,
    output logic [COUNTER_SIZE-1:0] main_index,
    // output logic [4:0] req_index,
    // output logic [4:0] main_index,
    // dispatcher
    output logic valid_task,
    output logic [1:0] task_type,
    output logic [TASK_WIDTH-1:0] task_data, // [x_i, x_j, P_i, P_j, rho_j]
    input wire [15:0] particle_count
);

    // This modules function:
    // Reads particles from memory and distributes them such that 
    // the computation for that specific particle can be fulfilled. 

    // 1. upon trigger, begin from particle 1
    // 2. read particle from memory, (later we will read all the other ones as well)
    // 3. distribute particle to updater

    localparam delay_cycles = (RAM_PERFORMANCE == "HIGH_PERFORMANCE") ? 1 : 0;

    logic [COUNTER_SIZE-1:0] i; // particle index i
    logic [COUNTER_SIZE-1:0] j; // particle index j
    // logic [4:0] i; // particle index i
    // logic [4:0] j; // particle index j

    logic [16*DIMS-1:0] x_i; // position of particle i
    logic [16-1:0] P_i; // pressure of particle i

    logic [COUNTER_SIZE:0] cycle_counter; // cycle counter
    // logic [4:0] cycle_counter; // cycle counter

    enum {DONE, INIT, DENSITIES, FORCES, PART_DONE} state, last_state;
    typedef enum bit [1:0] {DENSITY, FORCE} task_type_t;

    assign mem_write_enable = 0;
    assign main_index = i;
    assign is_density_task = last_state == DENSITIES;
    assign done = state == DONE; //  done with everything 
    assign reading_positions = state == DENSITIES && cycle_counter > 2 && cycle_counter < particle_count + 3;

    // We need to add position predictions
    logic [DIMS-1:0] [15:0] pos_change_result, pos_predict_result;
    logic [DIMS-1:0] pos_change_valid, pos_predict_valid;
    // logic [15:0] predict_step_in;

    localparam MULTI_CYCLES = 4;
    localparam ADDER_CYCLES = 4;

    // these are valid in when cycle_counter is within a certain range
    logic [DIMS-1:0] [15:0] vel_in;
    logic [MULTI_CYCLES-1:0] [DIMS-1:0] [15:0] pos_in; // pipelined position
    always_ff @( posedge clk_in ) begin 
        if (rst_in) begin
            vel_in <= 0;
            pos_in <= 0;
        end else begin
            // hardcoding for 2D
            vel_in <= mem_in[31:0];
            pos_in <= {pos_in[MULTI_CYCLES-2:0], mem_in[63:32]};
        end
    end

    generate 
        genvar l;
        for (l=0; l<DIMS; l=l+1) begin
            binary16_multi pos_change (
                .clk_in(clk_in),
                .rst(rst_in),
                .a(vel_in[l]),
                .b(PREDICTION_FACTOR),
                .data_valid_in(1'b1), // something to trigger the multiplication
                .result(pos_change_result[l]),
                .data_valid_out(pos_change_valid[l]),
                .busy()
            );
            binary16_adder pos_predict (
                .clk_in(clk_in),
                .rst(rst_in),
                .a(pos_in[MULTI_CYCLES-1][l]),
                .b(pos_change_result[l]),
                .data_valid_in(pos_change_valid[l]),
                .result(pos_predict_result[l]),
                .data_valid_out(pos_predict_valid[l]), // this gets output in the task_data
                .busy()
            );
        end
    endgenerate

    localparam PREDICT_STAGES = MULTI_CYCLES + ADDER_CYCLES;
    logic [PREDICT_STAGES-1:0] [15:0] pressure_pipe, density_reciprocal_pipe;
    always_ff @( posedge clk_in ) begin 
        if (rst_in) begin
            pressure_pipe <= 0;
            density_reciprocal_pipe <= 0;
        end else begin
            pressure_pipe <= {pressure_pipe[PREDICT_STAGES-2:0], pressure};
            density_reciprocal_pipe <= {density_reciprocal_pipe[PREDICT_STAGES-2:0], density_reciprocal};
        end
    end

    // Memory is now 64 wide with [p_x, p_y, v_x, v_y]
    always_ff @( posedge clk_in ) begin 
        if (rst_in) begin

            // state
            state <= DONE;
            last_state <= DONE;

            // memory
            // mem_write_enable <= 0;
            mem_enable <= 0;
            addr_out <= 0;

            // accumulation & storage
            next_sum <= 0;
            req_index <= 0;
            // requesting <= 0;
            // p_index <= 0;

            // dispatcher
            valid_task <= 0;
            task_type <= 0;
            task_data <= 0;

        end else begin
            case (state)
                DONE: begin
                    if (new_frame) begin
                        state <= INIT;
                    end
                    last_state <= DONE;
                end
                INIT: begin

                    mem_enable <= 1;
                    next_sum <= 1; // just have accumulator count to N terms for now
                    i <= 0;
                    j <= 0;
                    
                    // request p, v
                    addr_out <= 0; // x_1, v_1, x_2, whether to make each dim a different entry
                    req_index <= 0;
                    
                    cycle_counter <= 0;
                    state <= DENSITIES;

                end
                FORCES, DENSITIES: begin

                    next_sum <= 0;
                    valid_task <= 0;
                    
                    // TODO: Resync memory accesses to occur within the clock cycle
                    if (cycle_counter == 2 + ADDER_CYCLES + MULTI_CYCLES) begin
                        // predicted position
                        x_i <= pos_predict_result;
                        P_i <= pressure_pipe[PREDICT_STAGES-1];
                    end else if (cycle_counter > 2 + ADDER_CYCLES + MULTI_CYCLES) begin // submit results as tasks
                        if (state == DENSITIES) begin
                            task_data <= {x_i, pos_predict_result, 48'b0}; // x_i, x_j
                            task_type <= DENSITY;
                            // valid_task <= 1;
                        end else begin
                            if (cycle_counter != i + 3 + ADDER_CYCLES + MULTI_CYCLES) begin
                                task_data <= {x_i, pos_predict_result, P_i, pressure_pipe[PREDICT_STAGES-1], density_reciprocal_pipe[PREDICT_STAGES-1]}; // x_i, x_j
                            end else begin
                                task_data <= {x_i, pos_predict_result, 16'b0, 16'b0, density_reciprocal_pipe[PREDICT_STAGES-1]}; // should set force to 0
                                // task_data <= 0;
                            end
                            task_type <= FORCE;
                            // valid_task <= cycle_counter != i + 3 + ADDER_CYCLES + MULTI_CYCLES; // don't compute force on self
                        end
                            valid_task <= 1;
                        if (cycle_counter == particle_count + 3 + ADDER_CYCLES + MULTI_CYCLES) begin
                            state <= PART_DONE;
                            valid_task <= 0;
                        end
                    end 

                    if (cycle_counter < particle_count) begin
                        addr_out <= j; // x_1, v_1, x_2, whether to make each dim a different entry
                        j <= j + 1;
                        req_index <= j;
                    end else begin
                        // cycle_counter <= 0;
                        addr_out <= 0;
                        j <= 0;
                    end

                    cycle_counter <= cycle_counter + 1;
                    last_state <= state;
                end
                // FORCES: begin
                //     next_sum <= 0;
                //     valid_task <= 0;
                //     if (cycle_counter == 2) begin
                //         x_i <= mem_in;
                //         P_i <= pressure;
                //     end else if (cycle_counter > 2) begin
                //         task_data <= {x_i, mem_in, P_i, pressure, density_reciprocal}; // x_i, x_j
                //         task_type <= FORCE;
                //         valid_task <= 1;
                //         if (cycle_counter == particle_count + 3) begin
                //             state <= PART_DONE;
                //             valid_task <= 0;
                //         end
                //     end 

                //     if (cycle_counter < particle_count) begin
                //         addr_out <= j; // x_1, v_1, x_2, whether to make each dim a different entry
                //         req_index <= j;
                //         j <= j + 1;
                //     end else begin
                //         // cycle_counter <= 0;
                //         addr_out <= 0;
                //         j <= 0;
                //         req_index <= 0;
                //     end

                //     cycle_counter <= cycle_counter + 1;
                //     last_state <= state;
                // end
                PART_DONE: begin
                    if (done_accumulating) begin

                        next_sum <= 1;
                        cycle_counter <= 0;
                        j <= 0;

                        if (i < particle_count - 1) begin
                            i <= i + 1;
                            addr_out <= i + 1;
                            req_index <= i + 1;
                            state <= last_state;
                        end else begin
                            if (last_state == DENSITIES) begin
                                i <= 0;
                                addr_out <= 0; 
                                req_index <= 0;
                                state <= FORCES;
                            end else begin
                                mem_enable <= 0;
                                next_sum <= 0;
                                state <= DONE;
                            end
                        end

                    end
                end
            endcase
        end
    end

endmodule

`default_nettype wire