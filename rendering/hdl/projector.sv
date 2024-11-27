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

  logic [15:0] curr_f_x_in;
  logic [15:0] curr_f_y_in;
  logic [15:0] curr_f_z_in;

  typedef enum {IDLE, PROJECTING} project_state;
  project_state state; 

  always_ff @(posedge clk_in) begin 

    if(rst_in) begin 

      data_valid_out <= 0; 
      ready_out <= 1; 
      curr_f_x_in <= 0; 
      curr_f_y_in <= 0; 
      curr_f_z_in <= 0; 

    end else begin 
      
      case (state)  
        IDLE: begin 
          data_valid_out <= 0; 
          if(data_valid_in) begin 
            curr_f_x_in <= f_x_in; 
            curr_f_y_in <= f_y_in; 
            curr_f_z_in <= f_z_in; 
            ready_out <= 0; 
            state <= PROJECTING; 
          end
        end 
        PROJECTING: begin 
          if(rasterizer_ready) begin 
            f_center_x_pos <= curr_f_x_in; 
            f_center_y_pos <= curr_f_y_in; 
            f_center_depth <= curr_f_z_in; 
            f_radius <= SPHERE_RADIUS; 
            data_valid_out <= 1; 
            ready_out <= 1; 
            state<= IDLE; 
          end
        end 
      endcase
    end 

  end 

endmodule 
