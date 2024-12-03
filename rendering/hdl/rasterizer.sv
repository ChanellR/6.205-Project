`timescale 1ns / 1ps
`default_nettype none

module rasterizer 
  #(
    parameter WIDTH = 320,
    parameter HEIGHT = 180 
  )(
    input wire clk_in, 
    input wire rst_in,
    input wire [15:0] f_center_x_pos,
    input wire [15:0] f_center_y_pos,
    input wire [15:0] f_center_depth,
    input wire [15:0] f_radius,
    input wire data_valid_in, 
    output logic [10:0] hcount_out,
    output logic [9:0] vcount_out, 
    output logic new_pixel_out,
    output logic ready_out
  );
 
  logic [15:0] f_current_center_x_pos;
  logic [15:0] f_current_center_y_pos;
  logic [15:0] f_current_center_depth;
  logic [15:0] f_current_radius; 

  logic [10:0] center_hcount; 
  logic [9:0] center_vcount; 
  logic [4:0] int_radius; 

  logic painter_ready;

  float_to_int x_convert(
    .f_value(f_current_center_x_pos),
    .int_value(center_hcount)
  );
  float_to_int y_convert(
    .f_value(f_current_center_y_pos),
    .int_value(center_vcount)
  );
  float_to_int radius_convert(
    .f_value(f_current_radius),
    .int_value(int_radius)
  );

  painter painter_inst(
    .clk_in(clk_in), 
    .rst_in(rst_in), 
    .radius_in(int_radius),
    .data_valid_in(painter_ready),
    .hcount_in(center_hcount), 
    .vcount_in(center_vcount),
    .hcount_out(hcount_out), 
    .vcount_out(vcount_out),
    .data_valid_out(new_pixel_out),
    .ready_out(ready_out)
  );


  always_ff @(posedge clk_in) begin 
    if(rst_in) begin 
      f_current_center_x_pos <= 0;
      f_current_center_y_pos <= 0; 
      f_current_center_depth <= 0; 
    end else begin 
      //on data valid in, store the current projection data and begin rasterization
      //convert positions to integers 
      //convert depth to a smaller bit size 
      //check depth against depth buffer with hcount vcount determined 
      //if good, send hcount, vcount of center to painter module 
      // replace depth buffer hcountvcount with new depth 
      if(data_valid_in) begin 
        f_current_center_depth <= f_center_depth;
        f_current_center_x_pos <= f_center_x_pos; 
        f_current_center_y_pos <= f_center_y_pos; 
        f_current_radius <= f_radius; 
        painter_ready <= 1; 
      end else begin 
        painter_ready <= 0; 
      end 

    end
  end


endmodule 

`default_nettype wire