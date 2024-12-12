`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module update_buffer #(
    parameter ADDR_WIDTH = 2,                     // Specify RAM depth (number of entries)
    parameter RAM_WIDTH = 16                      // Specify RAM data width
    // parameter PARTICLE_COUNT = 4
) (
    input wire clk_in,
    input wire rst,
    input wire [ADDR_WIDTH-1:0] addr_in,
    input wire [RAM_WIDTH-1:0] mem_in,
    input wire data_valid_in,
    input wire activate,
    output logic [ADDR_WIDTH-1:0] addr_out,
    output logic [RAM_WIDTH-1:0] mem_out,
    output logic mem_write_enable,
    output logic done_swapping
);

    // This module will receive new positions from the particle updater and then 
    // upon receiving the ending signal, update the particle buffer

    logic [ADDR_WIDTH:0] current_addr, max_addr;
    logic reading_out;
    xilinx_true_dual_port_read_first_2_clock_ram  #(
        .RAM_WIDTH(RAM_WIDTH),
        .RAM_DEPTH(128), // position and velocity
        .RAM_PERFORMANCE("LOW_LATENCY") // right after
    ) position_buffer (
    // blk_mem_gen_0 property_storage (
        // density reciprocal
        // different if you are requesting or storing
        .addra(addr_in),
        // .addra(1'b1),
        .clka(clk_in),
        .wea(data_valid_in),
        // .wea(1'b1),
        .dina(mem_in),
        // .dina(16'hFFFF),
        .ena(1'b1),
        .douta(),
        .rsta(1'b0),
        .regcea(1'b1),
        // pressure
        .addrb(current_addr),
        .clkb(clk_in),
        .web(1'b0),
        .dinb(64'b0),
        .enb(1'b1),
        .doutb(mem_out),
        .rstb(1'b0),
        .regceb(1'b0)
    );

    enum {IDLE, STALL, READING} state;
    always_ff @( posedge clk_in ) begin
        if (rst) begin
            current_addr <= 0;
            max_addr <= 0;
            reading_out <= 0;
            addr_out <= 0;
            done_swapping <= 1; // should start already being done
            state <= IDLE;
        end else begin
            if (data_valid_in && addr_in > max_addr) begin
                max_addr <= addr_in;
            end 
            case (state)
                IDLE: begin
                    if (activate) begin
                        done_swapping <= 0;
                        current_addr <= 0;
                        // reading_out <= 1;
                        state <= STALL;
                    end
                end
                STALL: begin
                    state <= READING; // wait for inputs from particle_updater to save
                end
                READING: begin
                    current_addr <= current_addr + 1;
                    addr_out <= current_addr;
                    mem_write_enable <= 1;
                    if (current_addr > max_addr) begin
                        mem_write_enable <= 0;
                        // reading_out <= 0;
                        current_addr <= 0;
                        done_swapping <= 1;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end


endmodule

`default_nettype wire