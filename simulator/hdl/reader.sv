`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module reader #(
    parameter ADDR_WIDTH = 2,                     // Specify RAM depth (number of entries)
    parameter DATA_WIDTH = 16,                       // Specify RAM data width
    parameter PARTICLE_COUNTER_SIZE = 2,
    parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE" // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
) (
    input wire clk_in,
    input wire rst,
    // memory
    input wire trigger,
    input wire [DATA_WIDTH-1:0] mem_in,
    output logic [ADDR_WIDTH-1:0] addr_out, 
    output logic mem_write_enable,
    output logic mem_enable,
    // updater
    input wire update_finished,
    output logic [DATA_WIDTH-1:0] updater_out,  
    output logic [PARTICLE_COUNTER_SIZE-1:0] particle_idx,
    output logic trigger_update
);

    // This modules function:
    // Reads particles from memory and distributes them such that 
    // the computation for that specific particle can be fulfilled. 

    // 1. upon trigger, begin from particle 1
    // 2. read particle from memory, (later we will read all the other ones as well)
    // 3. distribute particle to updater

    localparam delay_cycles = (RAM_PERFORMANCE == "HIGH_PERFORMANCE") ? 1 : 0;
    logic [1:0] delay_counter;

    logic [ADDR_WIDTH-1:0] current_particle_idx;
    assign particle_idx = current_particle_idx;

    enum {IDLE, FETCH, SEND, WAIT} state;

    always_ff @( posedge clk_in ) begin 
        if (rst) begin

            // state
            state <= IDLE;
            current_particle_idx <= 0;
            delay_counter <= 0;

            // memory
            mem_write_enable <= 0;
            mem_enable <= 0;
            addr_out <= 0;

            // updater
            trigger_update <= 0;
            updater_out <= 0;
            
        end else begin
            case (state)
                IDLE: begin
                    mem_write_enable <= 0; 
                    if (trigger) begin
                        addr_out <= current_particle_idx; // read particle
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
                        state <= SEND;
                    end
                    // state <= SEND;
                end
                SEND: begin

                    trigger_update <= 1; // run computation
                    updater_out <= mem_in;
                    // particle_idx <= current_particle_idx;

                    state <= WAIT;
                end
                WAIT: begin
                    trigger_update <= 0;
                    if (update_finished) begin
                        state <= IDLE;
                        // current_particle_idx <= current_particle_idx + 1;
                    end
                end
            endcase
        end
    end

endmodule

`default_nettype wire