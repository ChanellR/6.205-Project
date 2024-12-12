`default_nettype none

module resetter #(
    parameter ADDR_WIDTH = 2,                     // Specify RAM depth (number of entries)
    parameter RAM_WIDTH = 32                       // Specify RAM data width
)  (
    input wire clk_in,
    input wire rst_in, 
    input wire restart,
    output logic [ADDR_WIDTH-1:0] addr_out,
    output logic [RAM_WIDTH-1:0] data_out,
    output logic busy,      
    input wire [15:0] particle_count
); 
    // This module will assign new positions to all particles and reset their velocities
    // Thinking of having this module randomly assign exponents and mantissas to create 
    // particle within the bounds of the simulation

    logic [15:0] random;
    lfsr_16 mlfsr (
        .clk_in(clk_in),
        .rst_in(restart),
        .seed_in(16'hABCD ^ random), // every time we restart, we want a new seed
        .q_out(random)
    );

    always_ff @( posedge clk_in ) begin
        if (rst_in == 1) begin
            addr_out <= 0;
            data_out <= 0;
            busy <= 0;
        end else if (busy) begin
            if (addr_out == (particle_count << 1) - 1) begin
                addr_out <= 0;
                data_out <= 0;
                busy <= 0;
            end else begin
                addr_out <= addr_out + 1;
                if (addr_out & 1'b0) begin 
                    // next is velocity
                    data_out <= 0;
                end else begin
                    data_out <= {random[12], 5'b01110, random[15:6], random[15], 5'b01110, random[9:0], 32'b0};
                end
            end
        end else if (restart) begin
            addr_out <= 0;
            data_out <= {random[12], 5'b01110, random[15:6], random[15], 5'b01110, random[9:0], 32'b0};
            busy <= 1;
        end
    end
    
endmodule