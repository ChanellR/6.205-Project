module projector 
  #(
    parameter SPHERE_RADIUS = 16'b0100_0101_0000_0000
  )(
  input wire clk_in, 
  input wire rst_in, 
  input wire [15:0] f_x_in, 
  input wire [15:0] f_y_in, 
  input wire [15:0] f_z_in,
  input wire rasterizer_ready,  
  input wire data_valid_in, 
  output logic [15:0] f_center_x_pos,
  output logic [15:0] f_center_y_pos,
  output logic [15:0] f_center_depth,
  output logic [15:0] f_radius,
  output logic data_valid_out,
  output logic ready_out
);

  // logic [10:0] current_hcount; 
  // logic [9:0] current_vcount; 

  // logic [15:0] radius; 
  // logic [10:0] center_hcount; 
  // logic [9:0] center_vcount;

  // logic [10:0] box_corner_x; 
  // logic [9:0] box_corner_y; 

  // logic [10:0] end_hcount; 
  // logic [9:0] end_vcount; 

  // logic [15:0] curr_x; 
  // logic [15:0] curr_y; 
  // logic next_pixel; 
  // logic next_pixel_pipe; 
  // logic next_pixel_pipe1; 
  // logic next_pixel_pipe2; 

  logic [15:0] curr_f_x_in;
  logic [15:0] curr_f_y_in;
  logic [15:0] curr_f_z_in;

  // always_comb begin 
  //   curr_x = center_hcount > current_hcount ? center_hcount - current_hcount : current_hcount - center_hcount;
  //   curr_y = center_vcount > current_vcount ? center_vcount - current_vcount : current_vcount - center_vcount;    
  // end

  // always_ff @(posedge clk_in) begin 
  //   next_pixel_pipe <= next_pixel; 
  //   next_pixel_pipe1 <= next_pixel_pipe; 
  //   next_pixel_pipe2 <= next_pixel_pipe1; 
  // end

  always_ff @(posedge clk_in) begin 

    if(rst_in) begin 

      // hcount_out <= 0; 
      // vcount_out <= 0; 
      // data_valid_out <= 0; 
      // current_hcount <= 0;
      // current_vcount <= 0; 
      // center_hcount <= 0; 
      // center_vcount <= 0;  
      // radius <= 0; 
      // box_corner_x <= 0; 
      // box_corner_y <= 0; 
      // ready_out <= 0; 
      // next_pixel <= 0; 
      data_valid_out <= 0; 
      ready_out <= 1; 
      curr_f_x_in <= 0; 
      curr_f_y_in <= 0; 
      curr_f_z_in <= 0; 

    end else begin 
      
      if(data_valid_in) begin 
        curr_f_x_in <= f_x_in; 
        curr_f_y_in <= f_y_in; 
        curr_f_z_in <= f_z_in; 

        if(rasterizer_ready) begin 
          f_center_x_pos <= curr_f_x_in; 
          f_center_y_pos <= curr_f_y_in; 
          f_center_depth <= curr_f_z_in; 
          f_radius <= SPHERE_RADIUS; 
          data_valid_out <= 1; 
        end
        ready_out <= 0; 

      end else begin 
        ready_out <= 1; 
        data_valid_out <= 0; 
      end 



    end 

  end 

endmodule 
