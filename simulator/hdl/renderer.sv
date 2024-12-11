`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module renderer #(
  parameter DIMS = 2,
    // down scaled 1280x720 by 4 to 320x180
  parameter TWICE_BOUNDS = 32'h4c004c00, // (8*2, 8*2)
  parameter SCREEN_BOUNDS = 32'h5D0059A0, // (320, 180)
  parameter HALF_SCREEN_BOUNDS = 32'h590055A0 // (320/2, 180/2)
) (
  input wire clk_pixel, 
  input wire clk_5x,
  input wire rst_in,
  input wire scale_select,
  input wire [16*DIMS-1:0] particle_position, //16-bit floating point input
  input wire data_valid_in, //valid data input
  input wire frame_swap,
  output logic [2:0] hdmi_tx_p, //hdmi output signals (positives) (blue, green, red)
  output logic [2:0] hdmi_tx_n, //hdmi output signals (negatives) (blue, green, red)
  output logic hdmi_clk_p, hdmi_clk_n, //differential hdmi clock
  output logic frame_drawn //frame drawn signal
  );

 
  logic [10:0] hcount; //hcount of system!
  logic [9:0] vcount; //vcount of system!
  logic hor_sync; //horizontal sync signal
  logic vert_sync; //vertical sync signal
  logic active_draw; //ative draw! 1 when in drawing region.0 in blanking/sync
  logic new_frame; //one cycle active indicator of new frame of info!
  logic [5:0] frame_count; //0 to 59 then rollover frame counter
  assign frame_drawn = new_frame; //output frame drawn signal

  //written by you previously! (make sure you include in your hdl)
  //default instantiation so making signals for 720p
  video_sig_gen mvg(
    .pixel_clk_in(clk_pixel),
    .rst_in(rst_in),
    .hcount_out(hcount),
    .vcount_out(vcount),
    .vs_out(vert_sync),
    .hs_out(hor_sync),
    .ad_out(active_draw),
    .nf_out(new_frame),
    .fc_out(frame_count)
  );

  // TODO: TESTING
  logic [DIMS-1:0] [15:0] test_position = 32'h4000_4000; // (2.0, 2.0) centered
  logic [DIMS-1:0] [31:0] transformed_position; // (320/2, 180/2) centered_on_screen
  logic valid_screen_coordinates;

  // Transform binary16 float positions to the screen space for rendering 2D
  transform_position #(
    .DIMS(DIMS),
    .TWICE_BOUNDS(TWICE_BOUNDS),
    .SCREEN_BOUNDS(SCREEN_BOUNDS),
    .HALF_SCREEN_BOUNDS(HALF_SCREEN_BOUNDS)
  ) tp (
    .clk_in(clk_pixel),
    .rst(rst_in),
    .f(particle_position),
    // .f(test_position),
    // .data_valid_in(hcount == 0 && vcount == 0),
    .data_valid_in(data_valid_in),
    .result(transformed_position),
    .data_valid_out(valid_screen_coordinates)
  );
  
  logic [15:0] addra, color_out;
  logic new_pixel_out;
  always_ff @( posedge clk_pixel ) begin : paste_particle
    if (rst_in) begin
      addra <= 0;
      color_out <= 0;
    end else begin
      addra <= transformed_position[1] + 320 * transformed_position[0];
      new_pixel_out <= valid_screen_coordinates;
      if (clearing_frame) begin
        color_out <= {5'h1F, 6'h0, 5'h0};
      end else begin
        color_out <= {5'h0, 6'h0, 5'h1F};
      end
    end
  end

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
    good_addrb <= (hcount<320)&&(vcount<180);
    good_add_pipe1 <= good_addrb; 
    good_add_pipe2 <= good_add_pipe1; 
    addrb <= (hcount) + 320*vcount;
  end

  always_ff @(posedge clk_pixel) begin
    if(hcount == 1279 && vcount == 719) begin 
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

  // //clock manager...creates 74.25 Hz and 5 times 74.25 MHz for pixel and TMDS
  // hdmi_clk_wiz_720p mhdmicw (
  //     .reset(0),
  //     .locked(locked),
  //     .clk_ref(clk_100mhz),
  //     .clk_pixel(clk_pixel),
  //     .clk_tmds(clk_5x));

  blk_mem_gen_0 frame_buffer (
    .addra(clearing_frame ? clear_addr : addra), //pixels are stored using this math
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
    .addra(clearing_frame2 ? clear_addr2 : addra), //pixels are stored using this math
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



  // logic clearing_buffer; // 0 or 1
  // always_ff @( posedge clk_pixel ) begin : frame_advancing
  //   if (rst_in) begin
  //     clearing_buffer <= 1'b1;
  //   end else if (new_frame) begin
  //     clearing_buffer <= ~clearing_buffer;
  //   end
  // end

  // logic [1:0] [15:0] frame_buff_raw; //data out of frame buffer (565)
  // logic [15:0] addrb; //used to lookup address in memory for reading from buffer
  // xilinx_true_dual_port_read_first_2_clock_ram #(
  //   .RAM_WIDTH(16),
  //   .RAM_DEPTH(320*180),
  //   .RAM_PERFORMANCE("HIGH_PERFORMANCE")
  // ) frame_buffer_0 (
  // // blk_mem_gen_0 frame_buffer_0 (
  //   .addra(addra), //pixels are stored using this math
  //   .clka(clk_pixel),
  //   .wea((clearing_buffer) ? new_pixel_out : 1'b0),
  //   // .wea(new_pixel_out),
  //   .dina(color_out),
  //   .ena(1'b1),
  //   .douta(), //never read from this side
  //   .rsta(1'b0),
  //   .regcea(1'b1),
  //   .addrb(addrb),//transformed lookup pixel
  //   .dinb(16'b0),
  //   .clkb(clk_pixel),
  //   .web(!clearing_buffer), // if clearing_buffer is 0, then clear memory
  //   // .web(1'b0),
  //   .enb(1'b1),
  //   .doutb(frame_buff_raw[0]),
  //   .rstb(1'b0),
  //   .regceb(1'b0)
  // );

  // xilinx_true_dual_port_read_first_2_clock_ram #(
  //   .RAM_WIDTH(16),
  //   .RAM_DEPTH(320*180),
  //   .RAM_PERFORMANCE("HIGH_PERFORMANCE")
  // ) frame_buffer_1 (
  // // blk_mem_gen_0 frame_buffer_1 (
  //   .addra(addra), //pixels are stored using this math
  //   .clka(clk_pixel),
  //   .wea((clearing_buffer) ? 1'b0 : new_pixel_out),
  //   .dina(color_out),
  //   .ena(1'b1),
  //   .douta(), //never read from this side
  //   .rsta(1'b0),
  //   .regcea(1'b1),
  //   .addrb(addrb),//transformed lookup pixel
  //   .dinb(16'b0),
  //   .clkb(clk_pixel),
  //   .web(clearing_buffer), // if clearing_buffer is 1, then clear memory
  //   .enb(1'b1),
  //   .doutb(frame_buff_raw[1]),
  //   .rstb(1'b0),
  //   .regceb(1'b0)
  // );

  // logic [2:0] valid_addr_pipe;
  // logic [10:0] hcount_pipe; //hcount of system!
  // logic [9:0] vcount_pipe; //vcount of system!
  // always_ff @(posedge clk_pixel) begin
  //   if (scale_select) begin // scaling
  //     valid_addr_pipe <= {valid_addr_pipe[1:0], (hcount<320)&&(vcount<180)};
  //     // hcount_pipe <= hcount;
  //     // vcount_pipe <= 320 * vcount;
  //     // addrb <= hcount_pipe + vcount_pipe;
  //     addrb <= hcount + 320 * vcount;
  //   end else begin
  //     valid_addr_pipe <= {valid_addr_pipe[1:0], (hcount<320*4)&&(vcount<180*4)};
  //     // hcount_pipe <= hcount >> 2;
  //     // vcount_pipe <= 320 * vcount[9:1]; 
  //     // addrb <= hcount_pipe + vcount_pipe;
  //     addrb <= ((hcount) >> 2) + 320*(vcount >> 2); 
  //   end
  // end

  // // read from the buffer being cleared, to reduce
  // logic [7:0] fb_red, fb_green, fb_blue;
  // logic [15:0] fb;
  // assign fb = (clearing_buffer) ? frame_buff_raw[1] : frame_buff_raw[0];
  // // assign fb = frame_buff_raw[0];
  // always_ff @(posedge clk_pixel)begin
  //   fb_red <= valid_addr_pipe[2]?{fb[15:11],3'b0}:8'b0;
  //   fb_green <= valid_addr_pipe[2]?{fb[10:5], 2'b0}:8'b0;
  //   fb_blue <= valid_addr_pipe[2]?{fb[4:0],3'b0}:8'b0;
  // end

  logic [7:0] red, green, blue; //red green and blue pixel values for output
  // always_comb begin
  //   red = fb_red; 
  //   green = fb_green; 
  //   blue = fb_blue; 
  // end
 
  // logic [9:0] tmds_10b [0:2]; //output of each TMDS encoder!
  // logic tmds_signal [2:0]; //output of each TMDS serializer!

  tmds_encoder tmds_red(
      .clk_in(clk_pixel),
      .rst_in(rst_in),
      .data_in(red),
      .control_in(2'b0),
      .ve_in(active_draw),
      .tmds_out(tmds_10b[2]));
  tmds_encoder tmds_green(
      .clk_in(clk_pixel),
      .rst_in(rst_in),
      .data_in(green),
      .control_in(2'b0),
      .ve_in(active_draw),
      .tmds_out(tmds_10b[1]));
  tmds_encoder tmds_blue(
      .clk_in(clk_pixel),
      .rst_in(rst_in),
      .data_in(blue),
      .control_in({vert_sync, hor_sync}),
      .ve_in(active_draw),
      .tmds_out(tmds_10b[0]));
 
  //three tmds_serializers (blue, green, red):
  tmds_serializer red_ser(
      .clk_pixel_in(clk_pixel),
      .clk_5x_in(clk_5x),
      .rst_in(rst_in),
      .tmds_in(tmds_10b[2]),
      .tmds_out(tmds_signal[2]));
  tmds_serializer green_ser(
      .clk_pixel_in(clk_pixel),
      .clk_5x_in(clk_5x),
      .rst_in(rst_in),
      .tmds_in(tmds_10b[1]),
      .tmds_out(tmds_signal[1]));
  tmds_serializer blue_ser(
      .clk_pixel_in(clk_pixel),
      .clk_5x_in(clk_5x),
      .rst_in(rst_in),
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
 
endmodule // top_level
`default_nettype wire