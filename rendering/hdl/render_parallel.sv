module render_parallel #(
  parameter NUM_INST = 4
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
//rendering module: hook up to particle buffer
  logic [NUM_INST-1:0] p_render_ready; 
  logic [NUM_INST-1:0] new_pixel_out; 
  logic [NUM_INST-1:0][15:0] color_out; 
  logic [NUM_INST-1:0][15:0] addr_out; 

  logic render_ready; 
  assign render_ready = |p_render_ready; 


  logic [15:0] f_x_in; 
  logic [15:0] f_y_in; 
  logic [15:0] f_z_in; 

  logic fifo_valid_out; 
  logic [47:0] fifo_out; 
  logic [47:0] buffer_out; 
  logic full_out; 

  fifo #(
    .DATA_WIDTH(48),
    .NUM_SLOTS(5)
  )particle_fifo(
    .clk_in(clk_pixel),
    .rst_in(sys_rst), 
    .data_valid_in(send_render),
    .receiver_ready(render_ready),
    .data_line({f_z_in, f_y_in, f_x_in}),
    .data_out(fifo_out),
    .full_out(full_out),
    .data_valid_out(fifo_valid_out)
  );

  bus_driver #(
    .NUM_OUTPUTS(NUM_INST), 
    .DATA_WIDTH(48)
  )
  particle_buffer_interface (
    .clk_in(clk_pixel), 
    .rst_in(sys_rst), 
    .data_valid_in(fifo_valid_out), 
    .data_line(fifo_out),
    .output_array(coords_out), 
    .valid_outputs(valid_outputs)
  );

  logic [NUM_INST-1:0] valid_outputs; 
  // logic [(NUM_INST*48)-1:0] buffer_array; 

  // assign render_f_x_in = {buffer_array[3][0],buffer_array[2][0],buffer_array[1][0],buffer_array[0][0]};
  // assign render_f_y_in = {buffer_array[3][1],buffer_array[2][1],buffer_array[1][1],buffer_array[0][1]};
  // assign render_f_z_in = {buffer_array[3][2],buffer_array[2][2],buffer_array[1][2],buffer_array[0][2]};

  logic [NUM_INST-1:0][2:0][15:0] coords_out;

  logic [NUM_INST-1:0][15:0] render_f_x_in; 
  logic [NUM_INST-1:0][15:0] render_f_y_in; 
  logic [NUM_INST-1:0][15:0] render_f_z_in;

  logic send_render;  

  logic [NUM_INST-1:0][1:0][15:0] output_array;

  generate 
    genvar i; 
    
    for (i = 0; i<NUM_INST; i=i+1) begin 
      render rendering_inst(
        .clk_in(clk_pixel), 
        .rst_in(sys_rst), 
        .f_x_in(coords_out[i][0]), 
        .f_y_in(coords_out[i][1]), 
        .f_z_in(coords_out[i][2]), 
        .data_valid_in(valid_outputs[i]),
        .render_color_out(output_array[i][0]), 
        .render_new_pixel_out(new_pixel_out[i]), 
        .render_ready(p_render_ready[i]), 
        .addr_out(output_array[i][1]) 
      ); 
    end
  endgenerate

  logic [1:0][15:0] arbiter_out;
  logic render_pixel_out; 

  arbiter  #(
    .DATA_WIDTH(32), 
    .NUM_INPUTS(NUM_INST)
  ) render_arbiter(
//   input wire clk_in, 
//   input wire rst_in, 
//   input wire [NUM_INPUTS-1:0] [DATA_WIDTH-1:0] data_line,
//   input wire [NUM_INPUTS-1:0] valid_array, 
//   output logic [DATA_WIDTH-1:0] data_out, 
//   output logic data_valid_out
// );
    .clk_in(clk_pixel), 
    .rst_in(sys_rst), 
    .data_line(output_array), 
    .valid_array(new_pixel_out), 
    .data_out(arbiter_out), 
    .data_valid_out(render_pixel_out)
  );

  // logic [15:0] render_color_out;
  // logic [15:0] render_addr_out; 
  assign render_color_out = arbiter_out[0];
  assign addr_out = arbiter_out[1]; 

endmodule 