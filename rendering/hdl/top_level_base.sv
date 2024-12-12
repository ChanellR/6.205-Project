`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module top_level_base(
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
 
  logic [7:0] red, green, blue; //red green and blue pixel values for output
 

  //rendering module: hook up to particle buffer
  logic render_ready; 
  logic new_pixel_out; 
  logic [15:0] color_out; 
  logic [15:0] addr_out; 

  logic [47:0] buffer_out; 

  particle_buffer pb(
    .clk_in(clk_pixel), 
    .rst_in(sys_rst), 
    .busy(~render_ready),
    .p_out(buffer_out), 
    .p_valid_out(send_render)
  );

  logic send_render;  

  render rendering_inst(
    .clk_in(clk_pixel), 
    .rst_in(sys_rst), 
    .f_x_in(buffer_out[0]), 
    .f_y_in(buffer_out[1]), 
    .f_z_in(buffer_out[2]), 
    .data_valid_in(send_render),
    .render_color_out(color_out), 
    .render_new_pixel_out(new_pixel_out), 
    .render_ready(render_ready), 
    .addr_out(addr_out)
  ); 

  logic active_draw_hdmi; 
  logic nf_hdmi; 
  logic [5:0] frame_count_hdmi; 
  logic vsync_hdmi; 
  logic hsync_hdmi; 
  logic [10:0] hcount_hdmi; 
  logic [9:0] vcount_hdmi; 

  video_sig_gen vsg
  (
  .pixel_clk_in(clk_pixel),
  .rst_in(sys_rst),
  .hcount_out(hcount_hdmi),
  .vcount_out(vcount_hdmi),
  .vs_out(vsync_hdmi),
  .hs_out(hsync_hdmi),
  .nf_out(nf_hdmi),
  .ad_out(active_draw_hdmi),
  .fc_out(frame_count_hdmi)
  );

  logic clearing_frame; 
  logic clearing_frame2; 

  logic [15:0] clear_addr; 
  logic [15:0] clear_addr2; 

  logic write_frame_2; 
  logic [15:0] frame_buff_raw; //data out of frame buffer (565)
  logic [15:0] frame_buff_raw_2; 
  logic [15:0] addrb; //used to lookup address in memory for reading from buffer
  logic good_addrb; //used to indicate within valid frame for scaling
  logic [15:0] fb_out; 
  
  logic [15:0] addrb_pipe1; 

  always_comb begin 
    if(write_frame_2) begin 
      fb_out = frame_buff_raw; 
    end else begin 
      fb_out = frame_buff_raw_2; 
    end
  end 

  logic [7:0] fb_red, fb_green, fb_blue;
  always_ff @(posedge clk_pixel)begin
    fb_red <= good_add_pipe2?{fb_out[15:11],3'b0}:8'b0;
    fb_green <= good_add_pipe2?{fb_out[10:5], 2'b0}:8'b0;
    fb_blue <= good_add_pipe2?{fb_out[4:0],3'b0}:8'b0;
  end

  logic good_add_pipe1; 
  logic good_add_pipe2; 

  always_ff @(posedge clk_pixel) begin
    good_addrb <= (hcount_hdmi<320)&&(vcount_hdmi<180);
    good_add_pipe1 <= good_addrb; 
    good_add_pipe2 <= good_add_pipe1; 
    addrb <= (hcount_hdmi) + 320*vcount_hdmi;
  end

  always_ff @(posedge clk_pixel) begin
    if(hcount_hdmi == 1279 && vcount_hdmi == 719) begin 
      write_frame_2 <= ~write_frame_2; 
    end 

    if(good_addrb) begin 
      if(write_frame_2) begin 
        clear_addr <= addrb; 
        clearing_frame <= 1; 
        clearing_frame2 <= 0; 
      end else begin 
        clear_addr2 <= addrb; 
        clearing_frame2 <= 1; 
        clearing_frame <= 0; 
      end
    end else begin 
      clearing_frame <= 0; 
      clearing_frame2 <= 0; 
    end

  end

  always_comb begin
    red = fb_red; 
    green = fb_green; 
    blue = fb_blue; 
  end
 
  logic [9:0] tmds_10b [0:2]; //output of each TMDS encoder!
  logic tmds_signal [2:0]; //output of each TMDS serializer!
 
  //three tmds_encoders (blue, green, red)
  //MISSING two more tmds encoders (one for green and one for blue)
  //note green should have no control signal like red
  //the blue channel DOES carry the two sync signals:
  //  * control_in[0] = horizontal sync signal
  //  * control_in[1] = vertical sync signal

  //clock manager...creates 74.25 Hz and 5 times 74.25 MHz for pixel and TMDS
  hdmi_clk_wiz_720p mhdmicw (
      .reset(0),
      .locked(locked),
      .clk_ref(clk_100mhz),
      .clk_pixel(clk_pixel),
      .clk_tmds(clk_5x));

  blk_mem_gen_0 frame_buffer (
    .addra(clearing_frame ? clear_addr : addr_out), //pixels are stored using this math
    .clka(clk_pixel),
    .wea((new_pixel_out && (~write_frame_2)) || clearing_frame),
    .dina(clearing_frame ? 0 : color_out),
    .ena(1'b1),
    .douta(), //never read from this side
    .addrb(addrb),//transformed lookup pixel
    .dinb(16'b0),
    .clkb(clk_pixel),
    .web(1'b0),
    .enb(1'b1),
    .doutb(frame_buff_raw)
  );

  blk_mem_gen_0 frame_buffer_2 (
    .addra(clearing_frame2 ? clear_addr2 : addr_out), //pixels are stored using this math
    .clka(clk_pixel),
    .wea((new_pixel_out && write_frame_2) || clearing_frame2),
    .dina(clearing_frame2 ? 0 : color_out),
    .ena(1'b1),
    .douta(), //never read from this side
    .addrb(addrb),//transformed lookup pixel
    .dinb(16'b0),
    .clkb(clk_pixel),
    .web(1'b0),
    .enb(1'b1),
    .doutb(frame_buff_raw_2)
  );
  
  tmds_encoder tmds_red(
      .clk_in(clk_pixel),
      .rst_in(sys_rst),
      .data_in(red),
      .control_in(2'b0),
      .ve_in(active_draw_hdmi),
      .tmds_out(tmds_10b[2]));

  tmds_encoder tmds_green(
      .clk_in(clk_pixel),
      .rst_in(sys_rst),
      .data_in(green),
      .control_in(2'b0),
      .ve_in(active_draw_hdmi),
      .tmds_out(tmds_10b[1]));
  tmds_encoder tmds_blue(
      .clk_in(clk_pixel),
      .rst_in(sys_rst),
      .data_in(blue),
      .control_in({vsync_hdmi, hsync_hdmi}),
      .ve_in(active_draw_hdmi),
      .tmds_out(tmds_10b[0]));
 
  //three tmds_serializers (blue, green, red):
  //MISSING: two more serializers for the green and blue tmds signals.
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
  
  // output buffers generating differential signals:
  // three for the r,g,b signals and one that is at the pixel clock rate
  // the HDMI receivers use recover logic coupled with the control signals asserted
  // during blanking and sync periods to synchronize their faster bit clocks off
  // of the slower pixel clock (so they can recover a clock of about 742.5 MHz from
  // the slower 74.25 MHz clock)

  OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
  OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
  OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
  OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));
  
    //   xilinx_true_dual_port_read_first_2_clock_ram #(
  //   .RAM_WIDTH(16),                       // Specify RAM data width
  //   .RAM_DEPTH(57600),                     // Specify RAM depth (number of entries)
  //   .RAM_PERFORMANCE("HIGH_PERFORMANCE"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
  //   .INIT_FILE("fb.mem")                        // Specify name/location of RAM initialization file if using one (leave blank if not)
  // ) frame_buffer (
  //   .addra(addr_out),   // Port A address bus, width determined from RAM_DEPTH
  //   .addrb(addrb),   // Port B address bus, width determined from RAM_DEPTH
  //   .dina(color_out),     // Port A RAM input data, width determined from RAM_WIDTH
  //   .dinb(16'b0),     // Port B RAM input data, width determined from RAM_WIDTH
  //   .clka(clk_pixel),     // Port A clock
  //   .clkb(clk_pixel),     // Port B clock
  //   .wea(new_pixel_out),       // Port A write enable
  //   .web(1'b0),       // Port B write enable
  //   .ena(1'b1),       // Port A RAM Enable, for additional power savings, disable port when not in use
  //   .enb(1'b1),       // Port B RAM Enable, for additional power savings, disable port when not in use
  //   .rsta(sys_rst),     // Port A output reset (does not affect memory contents)
  //   .rstb(sys_rst),     // Port B output reset (does not affect memory contents)
  //   .regcea(1'b1), // Port A output register enable
  //   .regceb(1'b1), // Port B output register enable
  //   .douta(),   // Port A RAM output data, width determined from RAM_WIDTH
  //   .doutb(frame_buff_raw)    // Port B RAM output data, width determined from RAM_WIDTH
  // );
endmodule // top_level
`default_nettype wire