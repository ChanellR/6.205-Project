`default_nettype none // prevents system from inferring an undeclared logic (good practice)

`ifdef SYNTHESIS
`define FPATH(X) `"X`"
`else /* ! SYNTHESIS */
`define FPATH(X) `"../../data/X`"
`endif  /* ! SYNTHESIS */

module top_draft_2
    (
        input wire          clk_100mhz, //100 MHz onboard clock
        input wire [15:0]   sw, //all 16 input slide switches
        input wire [3:0]    btn //all four momentary button switches
        // output logic [15:0] led, //16 green output LEDs (located right above switches)
        // output logic [2:0]  rgb0, //RGB channels of RGB LED0
        // output logic [2:0]  rgb1, //RGB channels of RGB LED1
        // //  input wire          cipo, // SPI controller-in peripheral-out
        // output logic [3:0]  copi,
        // output logic        dclk, cs, // SPI controller output signals
        // // seven segment
        // output logic [3:0]  ss0_an,//anode control for upper four digits of seven-seg display
        // output logic [3:0]  ss1_an,//anode control for lower four digits of seven-seg display
        // output logic [6:0]  ss0_c, //cathode controls for the segments of upper four digits
        // output logic [6:0]  ss1_c //cathod controls for the segments of lower four digits
    );

    //shut up those rgb LEDs for now (active high):
    // assign rgb1 = 0; //set to 0.
    // assign rgb0 = 0; //set to 0.

    //have btnd control system reset
    logic               sys_rst;
    assign sys_rst = btn[0];

    // logic [6:0] ss_c; //used to grab output cathode signal for 7s leds
    // assign ss0_c = ss_c;
    // assign ss1_c = ss_c;

    // logic [1:0] btn_pulses;
    // pulser #(2) mpulser (
    //     .clk_in(clk_100mhz),
    //     .rst_in(sys_rst),
    //     .inputs(btn[1:0]),
    //     .outputs(btn_pulses)
    // );

    localparam RAM_WIDTH = 16;
    localparam PARTICLE_COUNT = 4;
    localparam PARTICLE_COUNTER_SIZE = $clog2(PARTICLE_COUNT);

    localparam DIMS = 1; // x, y, z
    localparam ELEMENTS = PARTICLE_COUNT * DIMS * 2;
    localparam ADDR_WIDTH = $clog2(ELEMENTS);
    
    // Reader gets port A
    // logic [RAM_WIDTH-1:0]     dina;
    logic [RAM_WIDTH-1:0]     douta;
    logic [ADDR_WIDTH-1:0]     addra;
    logic wea; // write enable
    logic ena; // enable
    
    // Updater gets port B
    logic [RAM_WIDTH-1:0]     dinb;
    logic [RAM_WIDTH-1:0]     doutb;
    logic [ADDR_WIDTH-1:0]     addrb;
    logic web, enb;

    // Renderer gets port C
    logic [RAM_WIDTH-1:0]     doutc;
    logic [ADDR_WIDTH-1:0]     addrc;
    logic enable_stream;
    
    // Particle Buffer
    // MEMORY FORMAT:
    // 0: p0_x, p0_y, p0_z, p0_vx, p0_vy, p0_vz
    // 96: p1_x, p1_y, p1_z, p1_vx, p1_vy, p1_vz
    particle_buffer #(
        .RAM_WIDTH(RAM_WIDTH),
        .RAM_DEPTH(ELEMENTS),
        .INIT_FILE(`FPATH(particle.mem))
        // .RAM_PERFORMANCE("LOW_LATENCY")
    ) mparticle_buffer (
        // PORT A
        .addra(addra), // only reading from first for now
        .dina({RAM_WIDTH{1'b0}}), // we only use port A for reads!
        .clka(clk_100mhz),
        .wea(wea), // read only
        .ena(ena),
        .rsta(sys_rst), // disabling reset
        .regcea(1'b1),
        .douta(douta),
        // PORT B
        .addrb(addrb),
        .dinb(dinb),
        .clkb(clk_100mhz),
        .web(web), 
        .enb(enb),
        .rstb(sys_rst),
        .regceb(1'b1),
        .doutb(doutb), // we only use port B for writes!
        // PORT C
        .clkc(clk_100mhz),
        .stream(enable_stream),
        .addrc(addrc),
        .doutc(doutc)
    );

    // Accumulation & Storage
    logic [PARTICLE_COUNTER_SIZE-1:0] req_index, main_index;
    logic [RAM_WIDTH-1:0] density_reciprocal, pressure;
    logic done_accumulating, is_density_task, next_sum;

    // Dispatcher
    typedef enum logic [1:0] {DENSITY, FORCE} task_type_t;
    task_type_t task_type;
    logic [RAM_WIDTH*5-1:0] task_data;
    logic valid_task;

    logic new_frame, frame_done;
    assign new_frame = btn[1]; // trigger reader with button 1

    // Scheduler
    scheduler #(
        .PARTICLE_COUNT(PARTICLE_COUNT),
        .DIMS(DIMS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(RAM_WIDTH),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE")
    ) mscheduler (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),
        .done(frame_done),
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
        .task_data(task_data) 
    );

    logic [15:0] receiver_data;
    logic receiver_valid, terms_in_flight;

    // Compute 
    compute #(
        .DATA_WIDTH(RAM_WIDTH),
        .H(16'h4000)
    ) mcompute (
        .clk_in(clk_100mhz),
        .rst(sys_rst),
        .valid_task(valid_task),
        .task_type(task_type),
        .data_in(task_data),
        .data_out(receiver_data),
        .terms_in_flight(terms_in_flight),
        .data_valid_out(receiver_valid)
    );

    logic [31:0] accumulator_out;
    logic accumulator_data_valid;

    accumulator #(
        .PARTICLE_COUNT(PARTICLE_COUNT),
        .DIMS(DIMS),
        .MAX_QUEUE_SIZE(3)
    ) maccumulator (
        .clk_in(clk_100mhz),
        .rst(sys_rst),
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
        .data_valid_out(accumulator_data_valid)
    );


    // Updater
    logic update_finished;
    particle_updater #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(RAM_WIDTH),
        .PARTICLE_COUNTER_SIZE(PARTICLE_COUNTER_SIZE),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE")
    ) mp_updater (
        .clk_in(clk_100mhz),
        .rst(sys_rst),
        // reader
        .accumulator_in(accumulator_out), 
        .particle_idx(main_index),
        .trigger_update(accumulator_data_valid),
        .update_finished(update_finished),
        // memory
        .mem_in(doutb), 
        .addr_out(addrb), 
        .mem_out(dinb),
        .mem_write_enable(web),
        .mem_enable(enb)
    );
    
    // Frame Timer
    // start with 10 Hz, so that we are always in sync with the rendering FPGA, per second
    // logic [31:0] frame_counter;
    // counter frame_ticker ( 
    //     .clk_in(clk_100mhz),
    //     .rst_in(sys_rst),
    //     .period_in(100_000_000), // 100 MHz / 10 = 10_000_000
    //     .count_out(frame_counter)
    // );

    // logic start_frame;
    // always_ff @( posedge clk_100mhz ) begin : frame_start
    //     if (sys_rst) begin
    //         start_frame <= 0;
    //     end else if (frame_counter == 0) begin
    //         start_frame <= 1;
    //     end else begin
    //         start_frame <= 0;
    //     end
    // end

endmodule // top_level



`default_nettype wire