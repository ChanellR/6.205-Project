`timescale 1ns / 1ps
`default_nettype none

module render 
  #(
    parameter WIDTH = 320,
    parameter HEIGHT = 180 
  )(
    input wire clk_in, 
    input wire rst_in,
    input wire [15:0] f_x_in,
    input wire [15:0] f_y_in,
    input wire [15:0] f_z_in,
    input wire data_valid_in, 
    output logic new_pixel_out,
    output logic render_ready
  );

  logic [15:0] f_center_x_pos; 
  logic [15:0] f_center_y_pos; 
  logic [15:0] f_center_depth; 
  logic [15:0] f_radius; 
  logic new_center_valid; 
  logic [10:0] rasterizer_hcount_out;
  logic [9:0] rasterizer_vcount_out;

  logic projector_ready; 
  logic rasterizer_ready; 

  logic clk_pixel, clk_5x; //clock lines
  logic locked; //locked signal (we'll leave unused but still hook it up)
 
  logic [15:0] addr_out; 
  logic data_valid_out; 
  logic [15:0] color_out; 


  // //clock manager...creates 74.25 Hz and 5 times 74.25 MHz for pixel and TMDS
  // hdmi_clk_wiz_720p mhdmicw (
  //     .reset(0),
  //     .locked(locked),
  //     .clk_ref(clk_100mhz),
  //     .clk_pixel(clk_pixel),
  //     .clk_tmds(clk_5x));

  projector
  #(.SPHERE_RADIUS(16'b0100_0101_0000_0000))
  projector_inst (
    .clk_in(clk_in), 
    .rst_in(rst_in), 
    .f_x_in(f_x_in), 
    .f_y_in(f_y_in), 
    .f_z_in(f_z_in), 
    .data_valid_in(data_valid_in), 
    .rasterizer_ready(rasterizer_ready),
    .f_center_x_pos(f_center_x_pos), 
    .f_center_y_pos(f_center_y_pos), 
    .f_center_depth(f_center_depth), 
    .f_radius(f_radius), 
    .data_valid_out(new_center_valid), 
    .ready_out(projector_ready)
  );

  rasterizer rasterizer_inst (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .f_center_x_pos(f_center_x_pos),
    .f_center_y_pos(f_center_y_pos),
    .f_center_depth(f_center_depth), 
    .f_radius(f_radius), 
    .data_valid_in(new_center_valid), 
    .hcount_out(rasterizer_hcount_out), 
    .vcount_out(rasterizer_vcount_out), 
    .new_pixel_out(new_pixel_out), 
    .ready_out(rasterizer_ready)
  );

  pixel_manager pixel_manager_inst (
    .clk_in(clk_in),
    .rst_in(rst_in), 
    .data_valid_in(new_pixel_out),
    .hcount_in(rasterizer_hcount_out), 
    .vcount_in(rasterizer_vcount_out), 
    .addr_out(addr_out), 
    .data_valid_out(data_valid_out), 
    .color_out(color_out)
  );


  logic active_draw_hdmi; 
  logic nf_hdmi; 
  logic [7:0] frame_count_hdmi; 
  logic vsync_hdmi; 
  logic hsync_hdmi; 
  logic [10:0] hcount_hdmi; 
  logic [9:0] vcount_hdmi; 

  video_sig_gen vsg
  (
  .pixel_clk_in(clk_in),
  .rst_in(rst_in),
  .hcount_out(hcount_hdmi),
  .vcount_out(vcount_hdmi),
  .vs_out(vsync_hdmi),
  .hs_out(hsync_hdmi),
  .nf_out(nf_hdmi),
  .ad_out(active_draw_hdmi),
  .fc_out(frame_count_hdmi)
  );

  blk_mem_gen_0 frame_buffer (
    .addra(addr_out), //pixels are stored using this math
    .clka(clk_camera),
    .wea(data_valid_out),
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
  logic [FB_SIZE-1:0] addrb; //used to lookup address in memory for reading from buffer
  logic good_addrb; //used to indicate within valid frame for scaling

  logic [7:0] fb_red, fb_green, fb_blue;
  always_ff @(posedge clk_pixel)begin
    fb_red <= good_add_pipe2?{frame_buff_raw[15:11],3'b0}:8'b0;
    fb_green <= good_add_pipe2?{frame_buff_raw[10:5], 2'b0}:8'b0;
    fb_blue <= good_add_pipe2?{frame_buff_raw[4:0],3'b0}:8'b0;
  end

  logic good_add_pipe1; 
  logic good_add_pipe2; 

  always_ff @(posedge clk_pixel) begin
    good_addrb <= (hcount_hdmi<320)&&(vcount_hdmi<180);
    good_add_pipe1 <= good_addrb; 
    good_add_pipe2 <= good_add_pipe1; 
    addrb <= (319-hcount_hdmi) + 320*vcount_hdmi;
  end

  always_ff @(posedge clk_in) begin 
    if(rst_in) begin 
      render_ready <= 0; 
    end else begin 
      render_ready <= projector_ready; 
    end 
  end 

  // logic [9:0] tmds_10b [0:2]; //output of each TMDS encoder!
  // logic       tmds_signal [2:0]; //output of each TMDS serializer!

  // tmds_encoder tmds_red(
  //   .clk_in(clk_pixel),
  //   .rst_in(rst_in),
  //   .data_in(red),
  //   .control_in(2'b0),
  //   .ve_in(active_draw_hdmi),
  //   .tmds_out(tmds_10b[2]));

  // tmds_encoder tmds_green(
  //   .clk_in(clk_pixel),
  //   .rst_in(rst_in),
  //   .data_in(green),
  //   .control_in(2'b0),
  //   .ve_in(active_draw_hdmi),
  //   .tmds_out(tmds_10b[1]));

  // tmds_encoder tmds_blue(
  //   .clk_in(clk_pixel),
  //   .rst_in(rst_in),
  //   .data_in(blue),
  //   .control_in({vsync_hdmi,hsync_hdmi}),
  //   .ve_in(active_draw_hdmi),
  //   .tmds_out(tmds_10b[0]));

  //  //three tmds_serializers (blue, green, red):
  //  //MISSING: two more serializers for the green and blue tmds signals.
  //  tmds_serializer red_ser(
  //        .clk_pixel_in(clk_pixel),
  //        .clk_5x_in(clk_5x),
  //        .rst_in(rst_in),
  //        .tmds_in(tmds_10b[2]),
  //        .tmds_out(tmds_signal[2]));
  //  tmds_serializer green_ser(
  //        .clk_pixel_in(clk_pixel),
  //        .clk_5x_in(clk_5x),
  //        .rst_in(rst_in),
  //        .tmds_in(tmds_10b[1]),
  //        .tmds_out(tmds_signal[1]));
  //  tmds_serializer blue_ser(
  //        .clk_pixel_in(clk_pixel),
  //        .clk_5x_in(clk_5x),
  //        .rst_in(rst_in),
  //        .tmds_in(tmds_10b[0]),
  //        .tmds_out(tmds_signal[0]));

  //  //output buffers generating differential signals:
  //  //three for the r,g,b signals and one that is at the pixel clock rate
  //  //the HDMI receivers use recover logic coupled with the control signals asserted
  //  //during blanking and sync periods to synchronize their faster bit clocks off
  //  //of the slower pixel clock (so they can recover a clock of about 742.5 MHz from
  //  //the slower 74.25 MHz clock)
  //  OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
  //  OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
  //  OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
  //  OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));

endmodule 

`default_nettype wire