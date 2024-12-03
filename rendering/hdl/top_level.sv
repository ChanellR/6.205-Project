`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module top_level(
  input wire clk_100mhz, //crystal reference clock
  input wire [15:0] sw, //all 16 input slide switches
  input wire [3:0] btn, //all four momentary button switches
  output logic [15:0] led, //16 green output LEDs (located right above switches)
  output logic [2:0] rgb0, //rgb led
  output logic [2:0] rgb1, //rgb led
  output logic [2:0] hdmi_tx_p, //hdmi output signals (positives) (blue, green, red)
  output logic [2:0] hdmi_tx_n, //hdmi output signals (negatives) (blue, green, red)
  output logic hdmi_clk_p, hdmi_clk_n //differential hdmi clock
  );
 
  assign led = sw; //to verify the switch values
  //shut up those rgb LEDs (active high):
  assign rgb1 = 0;
  assign rgb0 = 0;
 
  //have btn[0] control system reset
  logic sys_rst;
  assign sys_rst = btn[0]; //reset is btn[0]
  logic game_rst;
  assign game_rst = btn[1]; //reset is btn[1]
 
  logic clk_pixel, clk_5x; //clock lines
  logic locked; //locked signal (we'll leave unused but still hook it up)
 
  //clock manager...creates 74.25 Hz and 5 times 74.25 MHz for pixel and TMDS
  hdmi_clk_wiz_720p mhdmicw (
      .reset(0),
      .locked(locked),
      .clk_ref(clk_100mhz),
      .clk_pixel(clk_pixel),
      .clk_tmds(clk_5x));
 
  logic [10:0] hcount; //hcount of system!
  logic [9:0] vcount; //vcount of system!
  logic hor_sync; //horizontal sync signal
  logic vert_sync; //vertical sync signal
  logic active_draw; //ative draw! 1 when in drawing region.0 in blanking/sync
  logic new_frame; //one cycle active indicator of new frame of info!
  logic [5:0] frame_count; //0 to 59 then rollover frame counter
 
  //written by you previously! (make sure you include in your hdl)
  //default instantiation so making signals for 720p
  video_sig_gen mvg(
      .pixel_clk_in(clk_pixel),
      .rst_in(sys_rst),
      .hcount_out(hcount),
      .vcount_out(vcount),
      .vs_out(vert_sync),
      .hs_out(hor_sync),
      .ad_out(active_draw),
      .nf_out(new_frame),
      .fc_out(frame_count));
 
  //rendering module: hook up to particle buffer
  // logic render_ready; 
  // logic new_pixel_out; 
  // logic [15:0] color_out, addr_out; 

  // render rendering_inst(
  //   .clk_in(clk_pixel), 
  //   .rst_in(sys_rst), 
  //   .f_x_in(16'h4000), 
  //   .f_y_in(16'h4000), 
  //   .f_z_in(16'h4000), 
  //   .data_valid_in(1'b1), 
  //   .addr_out(addr_out),
  //   .render_color_out(color_out), 
  //   .render_new_pixel_out(new_pixel_out), 
  //   .render_ready(render_ready)
  // );

  // down scaled 1280x720 by 4 to 320x180
  localparam DIMS = 2;
  localparam TWICE_BOUNDS = 32'h4c004c00; // (8*2, 8*2)
  localparam SCREEN_BOUNDS = 32'h5D0059A0; // (320, 180)
  localparam HALF_SCREEN_BOUNDS = 32'h590055A0; // (320/2, 180/2)

  logic [DIMS-1:0] [15:0] test_position = 32'h0; // (0, 0) centered
  logic [DIMS-1:0] [31:0] test_position_out; // (320/2, 180/2) centered_on_screen
  logic valid_screen_coordinates;

  // Transform binary16 float positions to the screen space for rendering 2D
  transform_position #(
    .DIMS(DIMS),
    .TWICE_BOUNDS(TWICE_BOUNDS),
    .SCREEN_BOUNDS(SCREEN_BOUNDS),
    .HALF_SCREEN_BOUNDS(HALF_SCREEN_BOUNDS)
  ) tp (
    .clk_in(clk_pixel),
    .rst(sys_rst),
    .f(test_position),
    .data_valid_in(1'b1),
    .result(test_position_out),
    .data_valid_out(valid_screen_coordinates)
  );

  logic [15:0] addra, color_out;
  logic new_pixel_out;
  always_ff @( posedge clk_pixel ) begin : blockName
    if (sys_rst) begin
      addra <= 0;
      color_out <= 0;
    end else begin
      addra <= test_position_out[1] + 320 * test_position_out[0];
      new_pixel_out <= valid_screen_coordinates;
      color_out <= {5'h0, 6'h0, 5'h1F};
    end
  end

  blk_mem_gen_0 frame_buffer (
    .addra(addra), //pixels are stored using this math
    .clka(clk_pixel),
    .wea(new_pixel_out),
    .dina(color_out),
    .ena(1'b1),
    .douta(), //never read from this side
    .addrb(addrb),//transformed lookup pixel
    .dinb(16'b0),
    .clkb(clk_pixel),
    .web(1'b0),
    .enb(1'b1),
    .doutb(frame_buff_raw)
  );

  logic [15:0] frame_buff_raw; //data out of frame buffer (565)
  logic [15:0] addrb; //used to lookup address in memory for reading from buffer
  logic good_addrb; //used to indicate within valid frame for scaling

  logic good_add_pipe1; 
  logic good_add_pipe2; 
  logic [7:0] fb_red, fb_green, fb_blue;
  always_ff @(posedge clk_pixel)begin
    fb_red <= good_add_pipe2?{frame_buff_raw[15:11],3'b0}:8'b0;
    fb_green <= good_add_pipe2?{frame_buff_raw[10:5], 2'b0}:8'b0;
    fb_blue <= good_add_pipe2?{frame_buff_raw[4:0],3'b0}:8'b0;
  end

  always_ff @(posedge clk_pixel) begin
    if (~sw[0]) begin // scaling
      good_addrb <= (hcount<320)&&(vcount<180);
      addrb <= hcount + 320 * vcount;
    end else begin
      good_addrb <= (hcount<320*4)&&(vcount<180*4);
      addrb <= ((hcount) >> 2) + 320*(vcount >> 2); 
    end
    good_add_pipe1 <= good_addrb; 
    good_add_pipe2 <= good_add_pipe1; 
  end

  logic [7:0] red, green, blue; //red green and blue pixel values for output
  always_comb begin
    red = fb_red; 
    green = fb_green; 
    blue = fb_blue; 
  end
 
  logic [9:0] tmds_10b [0:2]; //output of each TMDS encoder!
  logic tmds_signal [2:0]; //output of each TMDS serializer!

  tmds_encoder tmds_red(
      .clk_in(clk_pixel),
      .rst_in(sys_rst),
      .data_in(red),
      .control_in(2'b0),
      .ve_in(active_draw),
      .tmds_out(tmds_10b[2]));
  tmds_encoder tmds_green(
      .clk_in(clk_pixel),
      .rst_in(sys_rst),
      .data_in(green),
      .control_in(2'b0),
      .ve_in(active_draw),
      .tmds_out(tmds_10b[1]));
  tmds_encoder tmds_blue(
      .clk_in(clk_pixel),
      .rst_in(sys_rst),
      .data_in(blue),
      .control_in({vert_sync, hor_sync}),
      .ve_in(active_draw),
      .tmds_out(tmds_10b[0]));
 
  //three tmds_serializers (blue, green, red):
  tmds_serializer red_ser(
      .clk_pixel_in(clk_pixel),
      .clk_5x_in(clk_5x),
      .rst_in(sys_rst),
      .tmds_in(tmds_10b[2]),
      .tmds_out(tmds_signal[2]));
  tmds_serializer green_ser(
      .clk_pixel_in(clk_pixel),
      .clk_5x_in(clk_5x),
      .rst_in(sys_rst),
      .tmds_in(tmds_10b[1]),
      .tmds_out(tmds_signal[1]));
  tmds_serializer blue_ser(
      .clk_pixel_in(clk_pixel),
      .clk_5x_in(clk_5x),
      .rst_in(sys_rst),
      .tmds_in(tmds_10b[0]),
      .tmds_out(tmds_signal[0]));
  
  //output buffers generating differential signals:
  //three for the r,g,b signals and one that is at the pixel clock rate
  //the HDMI receivers use recover logic coupled with the control signals asserted
  //during blanking and sync periods to synchronize their faster bit clocks off
  //of the slower pixel clock (so they can recover a clock of about 742.5 MHz from
  //the slower 74.25 MHz clock)
  OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
  OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
  OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
  OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));
 
endmodule // top_level
`default_nettype wire