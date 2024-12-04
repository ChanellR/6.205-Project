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
  output logic [15:0] f_center_x_pos,
  output logic [15:0] f_center_y_pos,
  output logic [15:0] f_center_depth,
  output logic [15:0] f_radius,
  output logic data_valid_out,
  output logic ready_out
);

  // logic [15:0] curr_f_x_in;
  // logic [15:0] curr_f_y_in;
  // logic [15:0] curr_f_z_in;

  logic [2:0] [15:0] curr_f_array; 
  logic [2:0] screen_coordinates_valid; 
  logic [2:0] [15:0] result_f_array;
  logic [2:0] [15:0] saved_results; 

  logic transform_done; 
  logic start_proj; 
  logic read_ready; 


  transform_position
  transform_inst (
    .clk_in(clk_in),
    .rst(rst_in),
    .f(curr_f_array), 
    .data_valid_in(start_proj),
    .result(result_f_array),
    .data_valid_out(transform_done)
  );
    

  logic [31:0] counter; 

  always_comb begin 
    f_center_x_pos = saved_results[0]; 
    f_center_y_pos = saved_results[1];
    f_center_depth = saved_results[2]; 
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
      curr_f_array <= 0; 
      read_ready <= 0; 
      counter <= 0; 

    end else begin 
      
      case (state)  
        IDLE: begin 
          data_valid_out <= 0; 
          saved_results <= 0; 
          read_ready <= 0; 
          if(data_valid_in) begin 
            curr_f_array[0] <= f_x_in; 
            curr_f_array[1] <= f_y_in; 
            curr_f_array[2] <= f_z_in; 
            
            start_proj <= 1; 
            ready_out <= 0; 
            state <= PROJECTING; 
          end
        end 
        PROJECTING: begin 

          start_proj <= 0; 

          if(transform_done) begin 
            read_ready <= 1; 
            saved_results <= result_f_array;
          end


          if(rasterizer_ready && read_ready == 1) begin 
            // f_center_x_pos <= curr_f_x_in; 
            // f_center_y_pos <= curr_f_y_in; 
            // f_center_depth <= curr_f_z_in; 
            f_radius <= SPHERE_RADIUS; 
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
