`default_nettype none // prevents system from inferring an undeclared logic (good practice)

`ifdef SYNTHESIS
`define FPATH(X) `"X`"
`else /* ! SYNTHESIS */
`define FPATH(X) `"../../data/X`"
`endif  /* ! SYNTHESIS */

module simulator #(
    // parameter PARTICLE_COUNT = 3,

    parameter H = 16'h359A, // 0.35f
    parameter KERNEL_COEFF = 16'h57F4,
    parameter DIV_KERNEL_COEFF = 16'h5BF4,
    parameter DAMPING_FACTOR = 16'h3800, // 0.5
    
    parameter TIME_STEP = 16'h2E66, // 0.1 delta time per frame
    // parameter TARGET_DENSITY = 16'b0_10000_0000000000, // 2.0
    // parameter PRESSURE_CONST = 16'b0_01111_0000000000, // 1.0
    
    parameter COUNTER_SIZE = 16,
    parameter DIMS = 2, // x, y, z
    parameter BOUND = 32'h49004900 // [10.0f, 10.0f] haven't fully tested this yet
) (
    input wire clk_in, //100 MHz onboard clock,
    input wire sys_rst, //system reset button (active high)
    input wire restart_sim,
    // input wire enable_stream, 
    input wire new_frame,
    output logic [16*(DIMS)-1:0] particle_data_out,
    output logic [COUNTER_SIZE-1:0] particle_index_out,
    // output logic [3:0] particle_index_out,
    output logic valid_particle, // signals the particle is valid
    output logic frame_complete,
    // Simulation Config
    input wire [16-1:0] gravitational_constant, // in y direction
    input wire [15:0] particle_count,
    input wire [15:0] pressure_const,
    input wire [15:0] target_density
);

    localparam RAM_WIDTH = 16 * DIMS * 2; // 16 for each element in the vector, 2 for the vector itself
    localparam PARTICLE_COUNTER_SIZE = COUNTER_SIZE;
    // localparam PARTICLE_COUNTER_SIZE = 5; // COUNTER_SIZE;

    // localparam ELEMENTS = ;
    localparam ADDR_WIDTH = COUNTER_SIZE;

    // Reader gets port A
    // logic [RAM_WIDTH-1:0]     dina;
    logic [RAM_WIDTH-1:0]     douta;
    logic [ADDR_WIDTH-1:0]     addra;
    logic wea; // write enable
    logic ena; // enable
    
    // Updater gets port B
    logic [RAM_WIDTH-1:0]     dinb;
    logic [RAM_WIDTH-1:0]     doutb;
    logic [ADDR_WIDTH-1:0]     updater_addrb, buffer_addrb;
    logic web, enb;

    // Renderer gets port C
    logic [RAM_WIDTH-1:0]     doutc;
    logic [ADDR_WIDTH-1:0]     addrc;

    // for output to the rendering module
    // we will verify this by depending on scheduler timing
    assign particle_data_out = douta[63:32]; 
    logic [1:0] [ADDR_WIDTH-1:0] addra_pipe;
    always_ff @( posedge clk_in ) begin 
        if (sys_rst) begin
            addra_pipe <= 2'b0;
        end else begin
            addra_pipe <= {addra_pipe[0], addra};
        end
    end
    assign particle_index_out = addra_pipe[1] >> 1; // for position and velocity

    logic addrb_owner;
    always_ff @( posedge clk_in ) begin 
        if (sys_rst | resetting_sim) begin
            addrb_owner <= 1; // start on updater
        end else if (new_frame) begin
            addrb_owner <= 1;
        end else if (update_finished & scheduler_done) begin
            addrb_owner <= 0; // go to buffer
        end
    end

    // Particle Initialization  
    logic [ADDR_WIDTH-1:0] resetter_addr;
    logic [RAM_WIDTH-1:0] resetter_data;
    logic resetting_sim; // everything should be reset when this is occuring
    resetter #(
        // .PARTICLE_COUNT(PARTICLE_COUNT),
        .ADDR_WIDTH(ADDR_WIDTH),
        .RAM_WIDTH(RAM_WIDTH)
    ) mresetter (
        .clk_in(clk_in),
        .rst_in(sys_rst),
        .restart(restart_sim),
        .addr_out(resetter_addr),
        .data_out(resetter_data),
        .busy(resetting_sim),
        .particle_count(particle_count)
    );

    // Particle Buffer
    // MEMORY FORMAT:
    // 0: p0_x, p0_y, p0_z, p0_vx, p0_vy, p0_vz
    // 96: p1_x, p1_y, p1_z, p1_vx, p1_vy, p1_vz
    xilinx_true_dual_port_read_first_2_clock_ram #(
        .RAM_WIDTH(RAM_WIDTH),
        .RAM_DEPTH(128), // max number of particles
        .INIT_FILE(`FPATH(particle.mem))
        // .RAM_PERFORMANCE("LOW_LATENCY")
    ) mparticle_buffer (
        // PORT A
        .addra((resetting_sim) ? resetter_addr : addra),
        .dina((resetting_sim) ? resetter_data : {RAM_WIDTH{1'b0}}), 
        .clka(clk_in),
        .wea(wea | resetting_sim), 
        .ena(ena | resetting_sim), // probably need to set this high as well
        .rsta(sys_rst), // disabling reset
        .regcea(1'b1),
        .douta(douta),
        // PORT B
        .addrb((addrb_owner) ? updater_addrb : buffer_addrb),
        .dinb(dinb),
        .clkb(clk_in),
        .web(web), // write only
        .enb(1'b1),
        .rstb(sys_rst | resetting_sim),
        .regceb(1'b1),
        .doutb(doutb) // we only use port B for writes!
        // PORT C
        // .clkc(clk_in),
        // .stream(enable_stream),
        // .addrc(particle_index_out),
        // .doutc(particle_data_out)
    );


    // Accumulation & Storage
    logic [PARTICLE_COUNTER_SIZE-1:0] req_index, main_index;
    logic [16-1:0] density_reciprocal, pressure;
    logic done_accumulating, is_density_task, next_sum;

    localparam TASK_WIDTH = 16*7;
    logic [1:0] task_type;
    logic valid_task;
    logic [TASK_WIDTH-1:0] task_data; // [x_i, x_j, P_i, P_j, rho_j] x_i are vectors


    // Scheduler
    logic scheduler_done, reading_positions;
    assign valid_particle = reading_positions;
    scheduler #(
        // .PARTICLE_COUNT(PARTICLE_COUNT),
        .DIMS(DIMS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .RAM_WIDTH(RAM_WIDTH),
        .TASK_WIDTH(TASK_WIDTH),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE")
    ) mscheduler (
        .clk_in(clk_in),
        .rst_in(sys_rst | resetting_sim),
        .done(scheduler_done),
        // rendering
        .reading_positions(reading_positions),
        // memory
        .new_frame(new_frame),
        .mem_in(douta),
        .addr_out(addra), 
        .mem_write_enable(wea),
        .mem_enable(ena),
        // accuumlation & storage
        .density_reciprocal(density_reciprocal), 
        .pressure(pressure), 
        .done_accumulating(done_accumulating), 
        .is_density_task(is_density_task),
        .next_sum(next_sum), 
        .req_index(req_index),
        .main_index(main_index),
        // dispatcher
        .valid_task(valid_task),
        .task_type(task_type), 
        .task_data(task_data),
        // Simulation Config
        .particle_count(particle_count)
    );


    // Compute 
    logic [16*DIMS-1:0] receiver_data;
    logic receiver_valid, terms_in_flight;
    compute #(
        .TASK_WIDTH(TASK_WIDTH),
        .DIMS(DIMS),
        .H(H),
        .KERNEL_COEFF(KERNEL_COEFF),
        .DIV_KERNEL_COEFF(DIV_KERNEL_COEFF)
    ) mcompute (
        .clk_in(clk_in),
        .rst(sys_rst | resetting_sim),
        .valid_task(valid_task),
        .task_type(task_type),
        .data_in(task_data),
        .data_out(receiver_data),
        .terms_in_flight(terms_in_flight),
        .data_valid_out(receiver_valid),
        // Simulation Config
        .gravitational_constant(gravitational_constant)
    );

    // Accumulator
    logic [16*(DIMS+1)-1:0] accumulator_out;
    logic accumulator_data_valid;
    accum_storage #(
        // .PARTICLE_COUNT(PARTICLE_COUNT),
        .MAX_QUEUE_SIZE(3),
        .DIMS(DIMS)
        // .TARGET_DENSITY(TARGET_DENSITY)
        // .PRESSURE_CONST(PRESSURE_CONST)
    ) maccum_storage (
        .clk_in(clk_in),
        .rst(sys_rst | resetting_sim),
        // scheduler
        .is_density_task(is_density_task),
        .next_sum(next_sum),
        .main_index(main_index),
        .req_index(req_index),
        .density_reciprocal(density_reciprocal),
        .pressure(pressure),
        .done_accumulating(done_accumulating),
        // receiver
        .data_in(receiver_data),
        .data_valid_in(receiver_valid),
        .terms_in_flight(terms_in_flight),
        // updater
        .data_out(accumulator_out),
        .data_valid_out(accumulator_data_valid),
        // Simulation Config
        // .particle_count(particle_count)
        .pressure_const(pressure_const),
        .target_density(target_density)
    );

    // Updater
    logic update_finished, updater_to_buffer_valid, updater_we;
    logic [DIMS-1:0] colliding;
    logic [RAM_WIDTH-1:0] updater_to_buffer;
    particle_updater #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .RAM_WIDTH(RAM_WIDTH),
        .PARTICLE_COUNTER_SIZE(PARTICLE_COUNTER_SIZE),
        .DIMS(DIMS),
        .TIME_STEP(TIME_STEP), // 0.1 delta time per frame
        .BOUND(BOUND), // (-10.0, 10.0) bound
        .DAMPING_FACTOR(DAMPING_FACTOR),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE")
    ) mp_updater (
        .clk_in(clk_in),
        .rst(sys_rst | resetting_sim),
        // reader
        .accumulator_in(accumulator_out), 
        .particle_idx(main_index),
        .trigger_update(accumulator_data_valid),
        .update_finished(update_finished),
        // memory
        .mem_in(doutb), 
        .addr_out(updater_addrb), 
        // update_buffer
        .mem_out(updater_to_buffer),
        .mem_write_enable(updater_to_buffer_valid),
        .mem_enable(updater_we), // leave hanging
        // debugging
        // .colliding(colliding),
        // simulation config
        .gravitational_constant(gravitational_constant)
    );

    // Swap Buffer
    update_buffer #(
        .ADDR_WIDTH(ADDR_WIDTH), 
        .RAM_WIDTH(RAM_WIDTH)
        // .PARTICLE_COUNT(PARTICLE_COUNT)
    ) pupdate_buffer (
        .clk_in(clk_in),
        .rst(sys_rst | resetting_sim),
        // particle updater
        .addr_in(updater_addrb),
        .mem_in(updater_to_buffer),
        .data_valid_in(updater_to_buffer_valid),
        .activate(update_finished & scheduler_done), // when scheduler is DONE and the last update finished comes in
        .addr_out(buffer_addrb),
        .mem_out(dinb),
        .mem_write_enable(web),
        .done_swapping(frame_complete)
        // Simulation Config    
        // .particle_count(particle_count)
    );

endmodule // top_level



`default_nettype wire