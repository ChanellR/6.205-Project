module projector 
  #(
    parameter SPHERE_RADIUS = 16'b0100_0101_0000_0000, 
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
  input wire rasterizer_ready,  
  input wire data_valid_in, 
  // output logic [15:0] f_center_x_pos,
  // output logic [15:0] f_center_y_pos,
  // output logic [15:0] f_center_depth,
  // output logic [15:0] f_radius,
  output logic [15:0] int_radius, 
  output logic [10:0] hcount_out, 
  output logic [9:0] vcount_out, 
  output logic [15:0] depth_out, 
  output logic data_valid_out,
  output logic ready_out
);

  // logic [15:0] curr_f_x_in;
  // logic [15:0] curr_f_y_in;
  // logic [15:0] curr_f_z_in;

  logic [2:0] [15:0] curr_f_array; 
  logic [2:0] screen_coordinates_valid; 
  logic [2:0] [15:0] result_f_array;
  logic [3:0] [31:0] saved_results; 

  logic transform_done; 
  logic mvp_done; 
  logic start_proj; 
  logic read_ready; 
 
  logic [15:0] x_out; 
  logic [15:0] y_out; 
  logic [15:0] z_out; 
  logic [15:0] w; 

  logic [3:0][31:0] coords; 
  logic [3:0] round_out; 

  pipelined_mvp 
  MVP(
    .clk_in(clk_in), 
    .rst_in(rst_in), 
    .x(f_x_in), 
    .y(f_y_in), 
    .z(f_z_in),
    .data_valid_in(start_proj), 
    .x_out(curr_f_array[0]), 
    .y_out(curr_f_array[1]), 
    .z_out(curr_f_array[2]), 
    .w_out(w), 
    .data_valid_out(mvp_done)
  ); 

  transform_position
  transform_inst (
    .clk_in(clk_in),
    .rst(rst_in),
    .f(curr_f_array), 
    .w(w),
    .data_valid_in(mvp_done),
    .result(result_f_array),
    .data_valid_out(transform_done)
  );

  generate
    genvar i;
    for (i=0; i<4; i=i+1) begin
      if(i < 3) begin 
        truncate_float float_to_int(
          .clk_in(clk_in),
          .rst(rst_in),
          .f(result_f_array[i]),
          .data_valid_in(transform_done),
          .result(coords[i]),
          .data_valid_out(round_out[i])
        );
      end else begin 
        truncate_float float_to_int(
          .clk_in(clk_in),
          .rst(rst_in),
          .f(SPHERE_RADIUS),
          .data_valid_in(transform_done),
          .result(coords[i]),
          .data_valid_out(round_out[i])
        );
      end
    end
  endgenerate 

  logic [31:0] counter; 

  always_comb begin 
    hcount_out = saved_results[0];
    vcount_out = saved_results[1]; 
    depth_out = saved_results[2];
    int_radius = saved_results[3]; 
  end 

  typedef enum {IDLE, PROJECTING} project_state;
  project_state state; 

  always_ff @(posedge clk_in) begin 

    if(rst_in) begin 

      data_valid_out <= 0; 
      ready_out <= 1; 
      // curr_f_x_in <= 0; 
      // curr_f_y_in <= 0; 
      // curr_f_z_in <= 0; 
      // curr_f_array <= 0; 
      read_ready <= 0; 
      counter <= 0; 

    end else begin 
      
      case (state)  
        IDLE: begin

          data_valid_out <= 0; 
          saved_results <= 0; 
          read_ready <= 0; 

          if(data_valid_in) begin 

            // curr_f_array[0] <= f_x_in; 
            // curr_f_array[1] <= f_y_in; 
            // curr_f_array[2] <= f_z_in; 
            
            start_proj <= 1; 
            ready_out <= 0; 
            state <= PROJECTING; 
          end
        end 
        PROJECTING: begin 

          start_proj <= 0; 

          if(round_out[0]) begin 
            read_ready <= 1; 
            saved_results <= coords;
          end


          if(rasterizer_ready && read_ready == 1) begin 
            // f_center_x_pos <= curr_f_x_in; 
            // f_center_y_pos <= curr_f_y_in; 
            // f_center_depth <= curr_f_z_in; 
            // f_radius <= SPHERE_RADIUS; 
            data_valid_out <= 1; 
            ready_out <= 1; 
            state<= IDLE; 
            counter <= counter + 1; 
          end
        end 
      endcase
    end 

  end 

endmodule 
