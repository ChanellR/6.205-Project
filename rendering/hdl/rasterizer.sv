`timescale 1ns / 1ps
`default_nettype none

module rasterizer 
  #(
    parameter WIDTH = 320,
    parameter HEIGHT = 180 
  )(
    input wire clk_in, 
    input wire rst_in,
    // input wire [15:0] f_center_x_pos,
    // input wire [15:0] f_center_y_pos,
    // input wire [15:0] f_center_depth,
    // input wire [15:0] f_radius,
    input wire [15:0] radius_in, 
    input wire [10:0] hcount_in, 
    input wire [9:0] vcount_in, 
    input wire [15:0] depth_in, 
    input wire data_valid_in, 
    output logic [10:0] hcount_out,
    output logic [9:0] vcount_out, 
    output logic [15:0] depth_out, 
    output logic [31:0] addr_out, 
    output logic new_pixel_out,
    output logic ready_out
  );
 
  // logic [15:0] f_current_center_x_pos;
  // logic [15:0] f_current_center_y_pos;
  // logic [15:0] f_current_center_depth;
  // logic [15:0] f_current_radius; 

  // logic [10:0] center_hcount; 
  // logic [9:0] center_vcount; 
  // logic [4:0] int_radius; 

  // logic painter_ready;
  // logic x_ready; 
  // logic round_in; 

  // logic [3:0] [15:0] normalized_position_result; 
  // logic [3:0] screen_coordinates_valid; 
  // logic [3:0] [31:0] screen_coordinates;

  // // float_to_int x_convert(
  // //   .clk_in(clk_in), 
  // //   .rst_in(rst_in),
  // //   .data_valid_in(round_in), 
  // //   .f_value(f_current_center_x_pos),
  // //   .int_value(center_hcount), 
  // //   .data_valid_out(x_ready)
  // // );
  // assign center_hcount = screen_coordinates[0]; 
  // assign center_vcount = screen_coordinates[1]; 
  // assign depth_out = screen_coordinates[2]; 
  // assign int_radius = screen_coordinates[3]; 



  // float_to_int y_convert(
  //   .clk_in(clk_in), 
  //   .rst_in(rst_in),
  //   .data_valid_in(round_in), 
  //   .f_value(f_current_center_y_pos),
  //   .int_value(center_vcount)
  // );
  // float_to_int radius_convert(
  //   .clk_in(clk_in), 
  //   .rst_in(rst_in),
  //   .data_valid_in(round_in), 
  //   .f_value(f_current_radius),
  //   .int_value(int_radius)
  // );

  // generate
  //   genvar i;
  //   for (i=0; i<4; i=i+1) begin
  //     truncate_float float_to_int(
  //       .clk_in(clk_in),
  //       .rst(rst_in),
  //       .f(normalized_position_result[i]),
  //       .data_valid_in(round_in),
  //       .result(screen_coordinates[i]),
  //       .data_valid_out(screen_coordinates_valid[i])
  //     );
  //   end
  // endgenerate

  painter painter_inst(
    .clk_in(clk_in), 
    .rst_in(rst_in), 
    .radius_in(radius_in),
    .data_valid_in(data_valid_in),
    .hcount_in(hcount_in), 
    .vcount_in(vcount_in),
    .hcount_out(hcount_out), 
    .vcount_out(vcount_out),
    .addr_out(addr_out), 
    .data_valid_out(new_pixel_out),
    .ready_out(ready_out)
  );


  always_ff @(posedge clk_in) begin 
  //   if(rst_in) begin 
  //     f_current_center_x_pos <= 0;
  //     f_current_center_y_pos <= 0; 
  //     f_current_center_depth <= 0; 
  //   end else begin 
  //     //on data valid in, store the current projection data and begin rasterization
  //     //convert positions to integers 
  //     //convert depth to a smaller bit size 
  //     //check depth against depth buffer with hcount vcount determined 
  //     //if good, send hcount, vcount of center to painter module 
  //     // replace depth buffer hcountvcount with new depth 
      if(data_valid_in) begin 
        
  //       normalized_position_result[0] <= f_center_x_pos; 
  //       normalized_position_result[1] <= f_center_y_pos; 
  //       normalized_position_result[2] <= f_center_depth; 
  //       normalized_position_result[3] <= f_radius;

        
        depth_out <= depth_in; 

  //       round_in <= 1; 
  //     end else begin 
  //       round_in <= 0; 
      end 

  //     if(screen_coordinates_valid[0]) begin 
  //       painter_ready <= 1; 
  //     end else begin 
  //       painter_ready <= 0; 
  //     end 

  //   end
  end


endmodule 

`default_nettype wire