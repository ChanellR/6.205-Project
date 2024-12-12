`default_nettype none // prevents system from inferring an undeclared logic (good practice)

`ifdef SYNTHESIS
`define FPATH(X) `"X`"
`else /* ! SYNTHESIS */
`define FPATH(X) `"../../data/X`"
`endif  /* ! SYNTHESIS */

// module integration_top_level (
module top_level (
    input wire          clk_100mhz, //100 MHz onboard clock
    input wire [15:0]   sw, //all 16 input slide switches
    input wire [3:0]    btn, //all four momentary button switches
    output logic [15:0] led, //16 green output LEDs (located right above switches)
    output logic [2:0]  rgb0, //RGB channels of RGB LED0
    output logic [2:0]  rgb1, //RGB channels of RGB LED1
    // seven segment
    output logic [3:0]  ss0_an,//anode control for upper four digits of seven-seg display
    output logic [3:0]  ss1_an,//anode control for lower four digits of seven-seg display
    output logic [6:0]  ss0_c, //cathode controls for the segments of upper four digits
    output logic [6:0]  ss1_c, //cathod controls for the segments of lower four digits
    // hdmi
    output logic [2:0] hdmi_tx_p, //hdmi output signals (positives) (blue, green, red)
    output logic [2:0] hdmi_tx_n, //hdmi output signals (negatives) (blue, green, red)
    output logic hdmi_clk_p, hdmi_clk_n //differential hdmi clock
);

    //shut up those rgb LEDs for now (active high):
    assign rgb1 = 0; //set to 0.
    assign rgb0 = 0; //set to 0.

    //have btnd control system reset
    logic sys_rst;

    logic [6:0] ss_c; //used to grab output cathode signal for 7s leds
    assign ss0_c = ss_c;
    assign ss1_c = ss_c;

    logic clk_pixel, clk_5x; //clock lines
    logic locked; //locked signal (we'll leave unused but still hook it up)
 
    //clock manager...creates 74.25 Hz and 5 times 74.25 MHz for pixel and TMDS
    hdmi_clk_wiz_720p mhdmicw (
        .reset(0),
        .locked(locked),
        .clk_ref(clk_100mhz),
        .clk_pixel(clk_pixel),
        .clk_tmds(clk_5x)
    );

    logic [3:0] btn_pulses;
    pulser #(4) mpulser (
        .clk_in(clk_pixel),
        .rst_in(sys_rst),
        .inputs(btn[3:0]),
        .outputs(btn_pulses)
    );

    parameter DIMS = 2; // x, y, z
    parameter PARTICLE_COUNT = 20;
    parameter GRAVITATIONAL_CONSTANT = 16'hCA00; 
    // parameter GRAVITATIONAL_CONSTANT = 16'hC000; 

    // parameter H = 16'h359A; // 0.35f
    // parameter KERNEL_COEFF = 16'h57F4; // 127.27f
    // parameter DIV_KERNEL_COEFF = 16'h5BF4; // 254.54f
    // parameter DAMPING_FACTOR = 16'h3800; // 0.5

    parameter H = 16'h359A; // 0.25
    parameter KERNEL_COEFF = 16'h5FA4; // 489.0f
    parameter DIV_KERNEL_COEFF = 16'h63A4; // 978.0f
    parameter DAMPING_FACTOR = 16'h359A; // 0.35f

    parameter TIME_STEP = 16'h2843; // 1/30.0f delta time per frame
    parameter TARGET_DENSITY = 16'h4000; // 2.0f
    parameter PRESSURE_CONST = 16'h4800; // 8.0f

    parameter COUNTER_SIZE = 16;
    parameter BOUND = 32'h4000_4000; // [2.0f, 2.0f] haven't fully tested this yet
    parameter TWICE_BOUNDS = 32'h4400_4400; // (2*2, 2*2)
    
    parameter SCREEN_BOUNDS = 32'h5D0059A0; // (320, 180)
    parameter HALF_SCREEN_BOUNDS = 32'h590055A0; // (320/2, 180/2)

    logic [15:0] frames_created;
    evt_counter frame_counter (
        .clk_in(clk_pixel),
        .rst_in(sys_rst),
        .evt_in(frame_complete),
        .count_out(frames_created)
    );

    // NOTE: Making all particle counters 16-bits in width, just to avoid those other limitations

    // simulator
    logic restart_sim, enable_stream, start_frame, frame_complete, frame_drawn;
    logic [16*(DIMS)-1:0] particle_data;
    logic [COUNTER_SIZE-1:0] particle_index;
    logic [15:0] gravitational_constant = GRAVITATIONAL_CONSTANT;
    logic [15:0] particle_count = PARTICLE_COUNT;
    logic [15:0] pressure_const = PRESSURE_CONST;
    logic [15:0] target_density = TARGET_DENSITY;
    always_ff @( posedge clk_pixel ) begin 
        if (sys_rst) begin
            particle_count <= PARTICLE_COUNT;
            pressure_const <= PRESSURE_CONST;
            gravitational_constant <= GRAVITATIONAL_CONSTANT;
            target_density <= TARGET_DENSITY;
        end else if (btn_pulses[2]) begin
            if (sw[0]) begin
                particle_count <= sw; 
            end else begin
                target_density <= sw;
            end
        end else if (btn_pulses[3]) begin
            if (sw[0]) begin
                pressure_const <= sw;
            end else begin
                gravitational_constant <= sw;
            end 
        end
    end

    // Seven Segment Display
    seven_segment_controller mssc(.clk_in(clk_pixel),
                                .rst_in(sys_rst),
                                .val_in({(sw[0]) ? particle_count : target_density, (sw[0]) ? pressure_const : gravitational_constant}),
                                .cat_out(ss_c),
                                .an_out({ss0_an, ss1_an}));

    simulator  #(
        .H(H),
        .TIME_STEP(TIME_STEP),
        // .PARTICLE_COUNT(PARTICLE_COUNT),
        .DIMS(DIMS),
        .BOUND(BOUND),
        // .TARGET_DENSITY(TARGET_DENSITY),
        // .PRESSURE_CONST(PRESSURE_CONST),
        .KERNEL_COEFF(KERNEL_COEFF),
        .DIV_KERNEL_COEFF(DIV_KERNEL_COEFF)
    ) msimulator (
        .clk_in(clk_pixel),
        .sys_rst(sys_rst),
        .restart_sim(restart_sim),
        // .enable_stream(enable_stream), // takes 2 cycles like memory
        .new_frame(frame_drawn), // this will start the schduler
        .particle_data_out(particle_data),
        .particle_index_out(particle_index),
        .valid_particle(valid_particle_in),
        .frame_complete(frame_complete),
        // Simulation Config
        .gravitational_constant(gravitational_constant), // no gravity
        .particle_count(particle_count),
        .pressure_const(pressure_const),
        .target_density(target_density)
    );

    // This setup relies on the scheduler being ready at the right time
    // start the stream and then 
    // enable_stream pipeline for data_valid_in
    // we can instead, start a new frame, then wait 5 cycles for scheduler to start fetching all the positions in order, 
    // and then just leach off of douta and addra

    // renderer
    logic valid_particle_in, scale_select;
    renderer #( // 2D
        .DIMS(DIMS)
    ) mrenderer (
        .clk_pixel(clk_pixel),
        .clk_5x(clk_5x),
        .rst_in(sys_rst),
        .scale_select(scale_select),
        .particle_position(particle_data),
        .data_valid_in(valid_particle_in),
        .frame_swap(start_frame), // start reading from the previously written to buffer
        .hdmi_tx_p(hdmi_tx_p),
        .hdmi_tx_n(hdmi_tx_n),
        .hdmi_clk_p(hdmi_clk_p),
        .hdmi_clk_n(hdmi_clk_n),
        .frame_drawn(frame_drawn) // let's start a new frame as soon as we enter horizontal syncing
    );

    // on start_frame, we must start swap the frame, and begin streaming out positions from the 
    // particle buffer, to begin writing to the other frame_buffer.
    always_comb begin 
        sys_rst = btn[0];
        
        restart_sim = btn_pulses[1];
        // start_frame = btn_pulses[2];

        scale_select = sw[0];
    end
    
    // We can either wire it up to update as quickly as it can, 
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