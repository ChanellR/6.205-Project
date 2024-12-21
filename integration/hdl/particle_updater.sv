`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module particle_updater #(
    parameter ADDR_WIDTH = 2,                     // Specify RAM depth (number of entries)
    parameter RAM_WIDTH = 32,                       // Specify RAM data width
    parameter PARTICLE_COUNTER_SIZE = 2,
    parameter DIMS = 2, // x, y, z
    parameter TIME_STEP = 16'h2E66, // 0.1 delta time per frame
    parameter BOUND = 32'h49004900, // (-10.0, 10.0) bound
    // parameter DAMPING_FACTOR = 16'h3B9A, // 0.95 damping factor
    parameter DAMPING_FACTOR = 16'h3800, // 0.5 damping factor
    parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE" // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
) (
    input wire clk_in,
    input wire rst,
    // reader
    input wire [16*(DIMS+1)-1:0] accumulator_in, // [force_x, force_y, density_reciprocal]
    input wire [PARTICLE_COUNTER_SIZE-1:0] particle_idx,
    input wire trigger_update,
    output logic update_finished,
    // memory
    input wire [RAM_WIDTH-1:0] mem_in, 
    output logic [ADDR_WIDTH-1:0] addr_out, 
    output logic [RAM_WIDTH-1:0] mem_out,
    output logic mem_write_enable,
    output logic mem_enable,
    // testing
    // output logic [DIMS-1:0] colliding,
    // simulation config
    input wire [15:0] gravitational_constant
);

    // This module function:
    // Accumulates particle data, and performs on update
    // TODO: This function currently overwrites particle data during calculation
    // and should be edited to save the force data, and then update everything at once, pipelined.

    // 1. read particle from reader
    // 2. modify particle data
    // 3. write particle back to memory

    localparam delay_cycles = (RAM_PERFORMANCE == "HIGH_PERFORMANCE") ? 1 : 0;
    logic [1:0] delay_counter;

    // particle data
    logic [ADDR_WIDTH-1:0] current_particle_idx;
    logic [DIMS-1:0] [16-1:0] particle_position, particle_velocity, incident_force;
    logic [16-1:0] density_reciprocal;

    logic [DIMS-1:0] [15:0] BOUNDS;
    logic [DIMS-1:0] colliding;
    // logic [DIMS-1:0] colliding_after;
    assign BOUNDS = BOUND;

    // arithmetic unit
    logic [DIMS-1:0] [16-1:0] adder_a, adder_b, adder_result;
    logic [DIMS-1:0] adder_valid_in, adder_valid_out;
    logic [DIMS-1:0] [16-1:0] mul_a, mul_b, mul_result;
    logic [DIMS-1:0] mul_valid_in, mul_valid_out;
    generate
        genvar i;
        for (i = 0; i < DIMS; i = i + 1) begin : adder
            binary16_adder madder (
                .clk_in(clk_in),
                .rst(rst),
                .a(adder_a[i]),
                .b(adder_b[i]),
                .data_valid_in(adder_valid_in[i]),
                .result(adder_result[i]),
                .data_valid_out(adder_valid_out[i])
            );
            binary16_multi mmul (
                .clk_in(clk_in),
                .rst(rst),
                .a(mul_a[i]),
                .b(mul_b[i]),
                .data_valid_in(mul_valid_in[i]),
                .result(mul_result[i]),
                .data_valid_out(mul_valid_out[i])
            );
            abs_comp mabs_comp (
                .a(adder_result[i]),
                .b(BOUNDS[i]),
                .gt(colliding[i])
            );
            // abs_comp after_comp (
            //     .a(adder_result[i]),
            //     .b(BOUNDS[i]),
            //     .gt(colliding_after[i])
            // );
        end
    endgenerate

    enum {IDLE, GRAVITY, FETCH, ACCEL, DELTA_VEL, VELOCITY, DELTA_POS, POSITION, HANDLE_COLLISION, DAMPEN, WRITE_VEL, WRITE_POS, WRITEBACK} state;

    // Have some of the output signals come based on state purely
    // to reduce latency
    always_comb begin  
        update_finished = (state == IDLE && mem_write_enable);
        mem_enable = 1;
    end

    always_ff @( posedge clk_in ) begin 

        if (rst) begin
            // state
            state <= IDLE;
            current_particle_idx <= 0;
            incident_force <= 0;
            particle_position <= 0;
            particle_velocity <= 0;
            // memory
            mem_write_enable <= 0;
            // mem_enable <= 1;
            addr_out <= 0;
            mem_out <= 0;
            delay_counter <= 0;
            // adder
            adder_valid_in <= 0;
            adder_a <= 0;
            adder_b <= 0;
            // multiplier
            mul_valid_in <= 0;
            mul_a <= 0;
            mul_b <= 0;
            // debug
            // colliding <= 0;
            // colliding_after <= 0;
        end else begin
            case (state)
                IDLE: begin
                    // mem_enable <= 0;
                    mem_write_enable <= 0;
                    // update_finished <= 0;
                    if (trigger_update) begin
                        current_particle_idx <= particle_idx;
                        {incident_force, density_reciprocal} <= accumulator_in; 
                        // read velocity for the given particle
                        addr_out <= particle_idx; 
                        // mem_enable <= 1;
                        delay_counter <= 0;
                        state <= FETCH;
                    end
                end
                FETCH: begin
                    // mem_enable <= 0; // disable memory
                    if (delay_counter < delay_cycles + 1) begin
                        // addr_out <= (current_particle_idx * 2); // read velocity 
                        delay_counter <= delay_counter + 1;
                    end else begin
                        // addr_out <= (current_particle_idx * 2); // read position
                        {particle_position, particle_velocity} <= mem_in; // read velocity
                        // state <= ACCEL;
                        state <= GRAVITY;
                    end
                end
                GRAVITY: begin
                    // add gravitational acceleration
                    for (int i = 0; i < DIMS; i = i+1) begin
                        adder_a[i] <= incident_force[i]; // this is f_i / rho
                        adder_b[i] <= (i == 0) ? gravitational_constant : 16'b0; // this is g
                        adder_valid_in[i] <= 1;
                    end
                    state <= ACCEL;
                end
                ACCEL: begin
                    adder_valid_in <= 0;
                    if (&adder_valid_out) begin
                        for (int i = 0; i < DIMS; i = i + 1) begin
                            // mul_a[i] <= incident_force[i]; // this is f_i
                            mul_a[i] <= adder_result[i]; // this is f
                            mul_b[i] <= density_reciprocal; // this is 1 / rho
                            mul_valid_in[i] <= 1; // packed
                        end
                        // state <= GRAVITY;
                        state <= DELTA_VEL;
                    end
                end
                DELTA_VEL: begin
                    mul_valid_in <= 0;
                    if (&mul_valid_out) begin
                        // calculate acceleration
                        for (int i = 0; i < DIMS; i = i + 1) begin
                            mul_a[i] <= mul_result[i]; // this is f_i / rho + g
                            mul_b[i] <= TIME_STEP; // this is dt
                            mul_valid_in[i] <= 1;
                        end
                        state <= VELOCITY;
                    end
                end
                VELOCITY: begin 
                    mul_valid_in <= 0;
                    if (&mul_valid_out) begin
                        for (int i = 0; i < DIMS; i = i + 1) begin
                            adder_a[i] <= particle_velocity[i];
                            adder_b[i] <= mul_result[i]; // this is a_i * dt
                            adder_valid_in[i] <= 1;
                        end
                        state <= DELTA_POS;
                    end
                end
                DELTA_POS: begin
                    adder_valid_in <= 0;
                    if (&adder_valid_out) begin
                        for (int i = 0; i < DIMS; i = i + 1) begin
                            particle_velocity[i] <= adder_result[i];
                            mul_a[i] <= adder_result[i]; // this is v_i
                            mul_b[i] <= TIME_STEP; // this is dt
                            mul_valid_in[i] <= 1;
                        end
                        state <= POSITION; 
                    end
                end
                POSITION: begin
                    mul_valid_in <= 0;
                    if (&mul_valid_out) begin
                        for (int i = 0; i < DIMS; i = i + 1) begin
                            adder_a[i] <= particle_position[i];
                            adder_b[i] <= mul_result[i]; // this is v_i * dt
                            adder_valid_in[i] <= 1;
                        end
                       state <= HANDLE_COLLISION; 
                    end
                end
                HANDLE_COLLISION: begin
                    adder_valid_in <= 0;
                    if (&adder_valid_out) begin
                        // colliding <= 0;
                        for (int i = 0; i < DIMS; i = i + 1) begin
                            // check if particle is out of bounds
                            // if (out_of_bounds(adder_result[i], (BOUND & (16'hFFFF << i * 16)) >> i * 16)) begin // adder_result[i] is the new position
                            if (colliding[i]) begin
                                // TODO: sometimes the particle sticks for more than 1 frame
                                // bound position and reverse velocity
                                // why is this xor?
                                // colliding[i] <= 1;
                                particle_position[i] <= BOUNDS[i] ^ ((adder_result[i] & 16'h8000)); // stay on the same side
                                mul_a[i] <= particle_velocity[i] ^ (1 << 15); // reverse velocity
                                mul_b[i] <= DAMPING_FACTOR; // 0.9 damping factor
                            end else begin
                                particle_position[i] <= adder_result[i];
                                mul_a[i] <= particle_velocity[i];
                                mul_b[i] <= 16'h3c00; // multiply by 1
                            end
                            mul_valid_in[i] <= 1;
                        end
                        state <= DAMPEN;
                    end
                end
                DAMPEN: begin
                    mul_valid_in <= 0;
                    if (&mul_valid_out) begin
                        for (int i = 0; i < DIMS; i = i + 1) begin
                            particle_velocity[i] <= mul_result[i];
                        end
                        // state <= WRITE_VEL;
                        state <= WRITEBACK;
                    end
                end
                WRITEBACK: begin
                    addr_out <= current_particle_idx;
                    mem_out <= {particle_position, particle_velocity};
                    mem_write_enable <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule

module abs_comp (
    input wire [15:0] a,
    input wire [15:0] b,
    output wire gt
);
    
    assign gt = (a[14:10] > b[14:10]) || ((a[14:10] == b[14:10]) && (a[9:0] > b[9:0]));

endmodule

`default_nettype wire
