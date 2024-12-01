`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module scheduler #(
    parameter PARTICLE_COUNT = 4,
    parameter DIMS = 1, // x, y, z
    parameter ADDR_WIDTH = 4,                     // Specify RAM depth (number of entries)
    parameter DATA_WIDTH = 16,                       // Specify RAM data width
    parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE" // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
) (
    input wire clk_in,
    input wire rst_in,
    output logic done, // signals the end of the frame
    // memory
    input wire new_frame,
    input wire [DATA_WIDTH-1:0] mem_in,
    output logic [ADDR_WIDTH-1:0] addr_out, 
    output logic mem_write_enable,
    output logic mem_enable,
    // accumulation & storage
    input wire [DATA_WIDTH-1:0] density_reciprocal,
    input wire [DATA_WIDTH-1:0] pressure,
    input wire done_accumulating,
    output logic is_density_task,
    output logic next_sum, // signals the accumulation of a new sum
    output logic [$clog2(PARTICLE_COUNT)-1:0] req_index,
    output logic [$clog2(PARTICLE_COUNT)-1:0] main_index,
    // dispatcher
    output logic valid_task,
    output logic [1:0] task_type,
    output logic [DATA_WIDTH*5-1:0] task_data // [x_i, x_j, P_i, P_j, rho_j]
);

    // This modules function:
    // Reads particles from memory and distributes them such that 
    // the computation for that specific particle can be fulfilled. 

    // 1. upon trigger, begin from particle 1
    // 2. read particle from memory, (later we will read all the other ones as well)
    // 3. distribute particle to updater

    localparam delay_cycles = (RAM_PERFORMANCE == "HIGH_PERFORMANCE") ? 1 : 0;

    logic [$clog2(PARTICLE_COUNT)-1:0] i; // particle index i
    logic [$clog2(PARTICLE_COUNT)-1:0] j; // particle index j

    logic [DATA_WIDTH-1:0] x_i; // pressure of particle j
    logic [DATA_WIDTH-1:0] P_i; // pressure of particle i

    logic [$clog2(PARTICLE_COUNT):0] cycle_counter; // cycle counter

    enum {DONE, INIT, DENSITIES, FORCES, PART_DONE} state, last_state;
    typedef enum bit [1:0] {DENSITY, FORCE} task_type_t;

    assign mem_write_enable = 0;
    assign main_index = i;
    assign is_density_task = last_state == DENSITIES;
    assign done = state == DONE;

    // always_comb begin
    //     mem_enable = state != DONE;
    // end

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
                end
                INIT: begin

                    mem_enable <= 1;
                    next_sum <= 1; // just have accumulator count to N terms for now
                    i <= 0;
                    j <= 0;
                    
                    // request x_i
                    addr_out <= (0 * 2 * DIMS); // x_1, v_1, x_2, whether to make each dim a different entry
                    req_index <= 0;
                    
                    cycle_counter <= 0;
                    state <= DENSITIES;

                end
                DENSITIES: begin

                    next_sum <= 0;
                    valid_task <= 0;
                    
                    // TODO: Resync memory accesses to occur within the clock cycle
                    if (cycle_counter == 2) begin
                        x_i <= mem_in;
                    end else if (cycle_counter > 2) begin // submit results as tasks
                        task_data <= {x_i, mem_in, 48'b0}; // x_i, x_j
                        task_type <= DENSITY;
                        valid_task <= 1;
                        if (cycle_counter == PARTICLE_COUNT + 3) begin
                            state <= PART_DONE;
                            valid_task <= 0;
                        end
                    end 

                    if (cycle_counter < PARTICLE_COUNT) begin
                        addr_out <= (j * 2 * DIMS); // x_1, v_1, x_2, whether to make each dim a different entry
                        j <= j + 1;
                    end else begin
                        // cycle_counter <= 0;
                        addr_out <= 0;
                        j <= 0;
                    end

                    cycle_counter <= cycle_counter + 1;
                    last_state <= state;
                end
                FORCES: begin
                    next_sum <= 0;
                    valid_task <= 0;
                    if (cycle_counter == 2) begin
                        x_i <= mem_in;
                        P_i <= pressure;
                    end else if (cycle_counter > 2) begin
                        task_data <= {x_i, mem_in, P_i, pressure, density_reciprocal}; // x_i, x_j
                        task_type <= FORCE;
                        valid_task <= 1;
                        if (cycle_counter == PARTICLE_COUNT + 3) begin
                            state <= PART_DONE;
                            valid_task <= 0;
                        end
                    end 

                    if (cycle_counter < PARTICLE_COUNT) begin
                        addr_out <= (j * 2 * DIMS); // x_1, v_1, x_2, whether to make each dim a different entry
                        req_index <= j;
                        j <= j + 1;
                    end else begin
                        // cycle_counter <= 0;
                        addr_out <= 0;
                        j <= 0;
                        req_index <= 0;
                    end

                    cycle_counter <= cycle_counter + 1;
                    last_state <= state;
                end
                PART_DONE: begin

                    if (done_accumulating) begin

                        next_sum <= 1;
                        cycle_counter <= 0;
                        j <= 0;

                        if (i < PARTICLE_COUNT - 1) begin
                            i <= i + 1;
                            addr_out <= ((i + 1) * 2 * DIMS);
                            req_index <= i + 1;
                            state <= last_state;
                        end else begin
                            if (last_state == DENSITIES) begin
                                i <= 0;
                                addr_out <= (0 * 2 * DIMS); 
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