`timescale 1ns / 1ps
`default_nettype none

module render 
  #(
    parameter WIDTH = 320,
    parameter HEIGHT = 180, 
    parameter BOUNDS_X = 10, 
    parameter BOUNDS_Y = 10
  )(
    input wire clk_in, 
    input wire rst_in,
    input wire [15:0] f_x_in,
    input wire [15:0] f_y_in,
    input wire [15:0] f_z_in,
    input wire data_valid_in, 
    output logic render_new_pixel_out,
    output logic render_ready, 
    output logic [15:0] render_color_out, 
    output logic [15:0] addr_out
  );

  logic [15:0] f_center_x_pos; 
  logic [15:0] f_center_y_pos; 
  logic [15:0] f_center_depth; 
  logic [15:0] f_radius; 
  logic new_center_valid; 
  logic [10:0] rasterizer_hcount_out;
  logic [9:0] rasterizer_vcount_out;
  logic rasterizer_new_pixel_out; 

  logic projector_ready; 
  logic rasterizer_ready; 
  logic data_valid_out; 

  projector
  #(.SPHERE_RADIUS(16'b0100_0101_0000_0000), 
  .WIDTH(WIDTH), 
  .HEIGHT(HEIGHT), 
  .BOUNDS_X(BOUNDS_X), 
  .BOUNDS_Y(BOUNDS_Y))
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
    .new_pixel_out(rasterizer_new_pixel_out), 
    .ready_out(rasterizer_ready)
  );

  pixel_manager pixel_manager_inst (
    .clk_in(clk_in),
    .rst_in(rst_in), 
    .data_valid_in(rasterizer_new_pixel_out),
    .hcount_in(rasterizer_hcount_out), 
    .vcount_in(rasterizer_vcount_out), 
    .addr_out(addr_out), 
    .data_valid_out(render_new_pixel_out), 
    .color_out(render_color_out)
  );

  always_ff @(posedge clk_in) begin 
    if(rst_in) begin 
      render_ready <= 0; 
    end else begin 
      render_ready <= projector_ready; 
    end 
  end 

endmodule 

`default_nettype wire