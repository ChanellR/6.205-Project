`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module updater #(
    parameter ADDR_WIDTH = 2,                     // Specify RAM depth (number of entries)
    parameter DATA_WIDTH = 16,                       // Specify RAM data width
    parameter PARTICLE_COUNTER_SIZE = 2,
    parameter TIME_SCALE = 16'h2E66, // 0.1 delta time per frame
    parameter Y_BOUND = 16'h4900, // (-10.0, 10.0) bound
    parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE" // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
) (
    input wire clk_in,
    input wire rst,
    // reader
    input wire [DATA_WIDTH-1:0] reader_in, 
    input wire [PARTICLE_COUNTER_SIZE-1:0] particle_idx,
    input wire trigger_update,
    output logic update_finished,
    // memory
    input wire [DATA_WIDTH-1:0] mem_in, 
    output logic [ADDR_WIDTH-1:0] addr_out, 
    output logic [DATA_WIDTH-1:0] mem_out,
    output logic mem_write_enable,
    output logic mem_enable
);

    // This module function:
    // Accumulates particle data, and performs on update

    // 1. read particle from reader
    // 2. modify particle data
    // 3. write particle back to memory

    localparam delay_cycles = (RAM_PERFORMANCE == "HIGH_PERFORMANCE") ? 1 : 0;
    logic [1:0] delay_counter;

    // particle data
    logic [ADDR_WIDTH-1:0] current_particle_idx;
    logic [DATA_WIDTH-1:0] particle_position;
    logic [DATA_WIDTH-1:0] particle_velocity;

    // arithmetic unit
    logic [DATA_WIDTH-1:0] a, b, result;
    logic adder_valid_in, adder_valid_out;
    binary16_adder madder (
        .clk_in(clk_in),
        .rst(rst),
        .a(a),
        .b(b),
        .data_valid_in(adder_valid_in),
        .result(result),
        .data_valid_out(adder_valid_out)
    );

    logic [DATA_WIDTH-1:0] mul_a, mul_b, mul_result;
    logic mul_valid_in, mul_valid_out;
    binary16_multi mmul (
        .clk_in(clk_in),
        .rst(rst),
        .a(mul_a),
        .b(mul_b),
        .data_valid_in(mul_valid_in),
        .result(mul_result),
        .data_valid_out(mul_valid_out)
    );

    // Is value1 > value2
    function logic out_of_bounds(input logic [DATA_WIDTH-1:0] pos, input logic [DATA_WIDTH-1:0] bound);
        // Extract sign, exponent, and mantissa
        // logic sign1, sign2;
        logic [4:0] exp1, exp2;
        logic [9:0] mant1, mant2;

        // sign1 = pos[15];
        // sign2 = bound[15];
        exp1 = pos[14:10];
        exp2 = bound[14:10];
        mant1 = pos[9:0];
        mant2 = bound[9:0];

        out_of_bounds = (exp1 > exp2) | ((exp1 == exp2) & (mant1 > mant2));

    endfunction

    enum {IDLE, FETCH, VELOCITY, DELTA_POS, POSITION, HANDLE_COLLISION, WRITE_VEL, WRITE_POS} state;

    // Have some of the output signals come based on state purely
    // to reduce latency
    always_comb begin  
        update_finished = (state == WRITE_POS);
    end

    always_ff @( posedge clk_in ) begin 

        if (rst) begin

            // state
            state <= IDLE;
            current_particle_idx <= 0;
            particle_position <= 0;
            particle_velocity <= 0;

            // reader 
            // update_finished <= 0;

            // memory
            mem_write_enable <= 0;
            mem_enable <= 0;
            addr_out <= 0;
            mem_out <= 0;
            delay_counter <= 0;

            // adder
            adder_valid_in <= 0;
            a <= 0;
            b <= 0;

        end else begin
            case (state)
                IDLE: begin
                    mem_enable <= 0;
                    mem_write_enable <= 0;
                    // update_finished <= 0;
                    if (trigger_update) begin
                        current_particle_idx <= particle_idx;
                        particle_position <= reader_in; 

                        // read velocity for the given particle
                        addr_out <= (particle_idx * 2) + 1; 
                        mem_enable <= 1;
                        delay_counter <= 0;
                        state <= FETCH;
                    end
                end
                FETCH: begin
                    mem_enable <= 0; // disable memory
                    if (delay_counter < delay_cycles) begin
                        delay_counter <= delay_counter + 1;
                    end else begin
                        state <= VELOCITY;
                    end
                end
                VELOCITY: begin
                    a <= mem_in;
                    b <= 16'hC000; // subtract 2.0
                    adder_valid_in <= 1;
                    state <= DELTA_POS;
                end
                DELTA_POS: begin
                    adder_valid_in <= 0;
                    if (adder_valid_out) begin
                        particle_velocity <= result;
                        mul_a <= result;
                        mul_b <= TIME_SCALE; // update position
                        mul_valid_in <= 1;
                        state <= POSITION; 
                    end
                end
                POSITION: begin
                    mul_valid_in <= 0;
                    if (mul_valid_out) begin
                       a <= particle_position;
                       b <= mul_result; // this is v * dt
                       adder_valid_in <= 1;
                       state <= HANDLE_COLLISION; 
                    end
                end
                HANDLE_COLLISION: begin
                    adder_valid_in <= 0;
                    if (adder_valid_out) begin
                        // check if particle is out of bounds
                        if (out_of_bounds(result, Y_BOUND)) begin
                            // TODO: sometimes the particle sticks for more than 1 frame
                            // bound position and reverse velocity
                            particle_position <= Y_BOUND ^ (result[15] << 15); // stay on the same side
                            particle_velocity <= particle_velocity ^ (1 << 15); // reverse velocity
                        end else begin
                            particle_position <= result;
                        end
                        state <= WRITE_VEL;
                    end
                end
                WRITE_VEL: begin
                    
                    // write velocity back to memory
                    addr_out <= (current_particle_idx * 2) + 1;
                    mem_write_enable <= 1;
                    mem_enable <= 1;
                    mem_out <= particle_velocity;
                    
                    // update position
                    // particle_position <= result;
                    
                    state <= WRITE_POS;

                end
                WRITE_POS: begin
                    addr_out <= (current_particle_idx * 2);
                    mem_out <= particle_position;
                    state <= IDLE;
                end
            endcase
        end

    end

endmodule

`default_nettype wire