module painter (
  input wire clk_in, 
  input wire rst_in, 
  input wire [16:0] radius_in, 
  input wire data_valid_in, 
  input wire [10:0] hcount_in,
  input wire [9:0] vcount_in, 
  output logic [10:0] hcount_out, 
  output logic [9:0] vcount_out, 
  output logic data_valid_out,
  output logic ready_out
);

  logic [10:0] current_hcount; 
  logic [9:0] current_vcount; 

  logic [15:0] radius; 
  logic [10:0] center_hcount; 
  logic [9:0] center_vcount;

  logic [10:0] box_corner_x; 
  logic [9:0] box_corner_y; 

  logic [10:0] end_hcount; 
  logic [9:0] end_vcount; 

  logic [15:0] curr_x; 
  logic [15:0] curr_y; 
  logic next_pixel; 
  logic next_pixel_pipe; 
  logic next_pixel_pipe1; 
  logic next_pixel_pipe2; 


  always_comb begin 
    curr_x = center_hcount > current_hcount ? center_hcount - current_hcount : current_hcount - center_hcount;
    curr_y = center_vcount > current_vcount ? center_vcount - current_vcount : current_vcount - center_vcount;    
  end

  always_ff @(posedge clk_in) begin 
    next_pixel_pipe <= next_pixel; 
    next_pixel_pipe1 <= next_pixel_pipe; 
    next_pixel_pipe2 <= next_pixel_pipe1; 
  end

  typedef enum {IDLE, PAINTING} paint_state;

  paint_state state; 

  always_ff @(posedge clk_in) begin 

    if(rst_in) begin 

      hcount_out <= 0; 
      vcount_out <= 0; 
      data_valid_out <= 0; 
      current_hcount <= 0;
      current_vcount <= 0; 
      center_hcount <= 0; 
      center_vcount <= 0;  
      radius <= 0; 
      box_corner_x <= 0; 
      box_corner_y <= 0; 
      state <= IDLE; 
      ready_out <= 1; 
      next_pixel <= 0; 

    end else begin 
      case (state)  
        IDLE: begin 
          ready_out <= 1; 
          next_pixel <= 0; 
          next_pixel_pipe <= 0; 
          next_pixel_pipe1 <= 0; 
          next_pixel_pipe2 <= 0; 
          if(data_valid_in) begin 
            state <= PAINTING; 
            current_hcount <= hcount_in - radius_in; 
            current_vcount <= vcount_in - radius_in; 
            radius <= radius_in; 
            center_hcount <= hcount_in; 
            center_vcount <= vcount_in; 
            box_corner_x <= hcount_in - radius_in; 
            box_corner_y <= vcount_in - radius_in; 
            end_hcount <= hcount_in + radius_in; 
            end_vcount <= vcount_in + radius_in; 
            ready_out <= 0; 
            next_pixel <= 1; 
          end
        end
        PAINTING: begin 
          
          if(current_vcount == end_vcount) begin 
            state <= IDLE; 
            ready_out <= 1; 
          end else begin 

            if(next_pixel_pipe2) begin 
              if(current_hcount <= end_hcount - 1) begin 
                current_hcount <= current_hcount + 1; 
              end else begin 
                //calculation 
                current_hcount <= box_corner_x; 
                current_vcount <= current_vcount + 1; 
              end
              next_pixel <= 1; 
            end else begin 
              next_pixel <= 0; 
            end

            if(curr_x * curr_x + curr_y * curr_y < radius * radius) begin 
              data_valid_out <= 1; 
              hcount_out <= current_hcount; 
              vcount_out <= current_vcount; 
            end else begin 
              data_valid_out <= 0; 
            end 

          end
        end

    endcase
  end 

  end 

endmodule 
