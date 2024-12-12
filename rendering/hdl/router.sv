module router 
#(
  parameter NUM_INPUTS = 4,
  parameter NUM_OUTPUTS = 4,
  parameter GRID_HEIGHT = 2, 
  parameter GRID_WIDTH = 2,
  parameter SCREEN_WIDTH = 320, 
  parameter SCREEN_HEIGHT = 180, 
  parameter DATA_WIDTH = 16, 
  parameter DATA_VALUES = 4
)(
  input wire clk_in, 
  input wire rst_in, 
  input wire [NUM_INPUTS-1:0] [(DATA_WIDTH*DATA_VALUES)-1:0] data_line,
  input wire [NUM_INPUTS-1:0] valid_array, 
  output logic [NUM_OUTPUTS-1:0] [(DATA_WIDTH*(DATA_VALUES+4))-1:0] output_array, 
  output logic [NUM_OUTPUTS-1:0] valid_outputs
);

  logic [NUM_INPUTS-1:0] [DATA_WIDTH-1:0] stored_values; 
  logic [NUM_INPUTS-1:0] todo;
  logic [NUM_INPUTS-1:0] current_ix; 

  counter cycles(.clk_in(clk_in),
                .rst_in(rst_in),
                .period_in(NUM_INPUTS),
                .count_out(current_ix)
  );

  logic [$clog2(NUM_OUTPUTS)-1:0] selector; 
  // assign selector = stored_values[current_ix] % NUM_OUTPUTS;
  logic [DATA_WIDTH-1:0] curr_data;
  logic [11:0] data_hcount, data_vcount; 
  // assign curr_data = fifo[current_ix]; 
  assign data_hcount = data_out[15:0]; 
  assign data_vcount = data_out[31:16]; 

  logic [DATA_WIDTH-1:0] u; 
  logic [DATA_WIDTH-1:0] v;

  localparam H_GRID = SCREEN_WIDTH/GRID_WIDTH; 
  localparam V_GRID = SCREEN_HEIGHT/GRID_HEIGHT;

  logic [GRID_HEIGHT-1:0] horizontal_one_hot; 
  logic [GRID_HEIGHT-1:0] vertical_one_hot; 
  logic [DATA_WIDTH-1:0] new_hcount; 
  logic [DATA_WIDTH-1:0] new_vcount; 
  

  always_comb begin 
    for(int j = 0; j<GRID_HEIGHT; j=j+1) begin 
      if(data_hcount >= j*H_GRID  && data_hcount > (j+1) * H_GRID) begin 
        horizontal_one_hot[j] = 1; 
      end else begin 
        horizontal_one_hot[j] = 0; 
      end 
    end 

    for(int j = 0; j<GRID_WIDTH; j=j+1) begin 
      if(data_vcount >= j*V_GRID  && data_vcount > (j+1) * V_GRID) begin 
        vertical_one_hot[j] = 1; 
      end else begin 
        vertical_one_hot[j] = 0; 
      end 
    end 

    case(vertical_one_hot) 
      0: v = 0; 
      1: v = 1;
      1<<1: v = 2; 
      1<<2: v = 3; 
      1<<4: v = 4; 
      1<<5: v = 5;
      1<<6: v = 6; 
      1<<7: v = 7;
      1<<8: v = 8; 
      default: v= 0; 
    endcase 

    case(horizontal_one_hot) 
      0: u = 0; 
      1: u = 1;
      1<<1: u = 2; 
      1<<2: u = 3;
      1<<4: u = 4; 
      1<<5: u = 5;
      1<<6: u = 6; 
      1<<7: u = 7; 
      1<<8: u = 8; 
      default: u=0;
    endcase 

    selector = u+(v*GRID_WIDTH); 
    new_hcount = data_hcount - (u*GRID_WIDTH); 
    new_vcount = data_vcount - (v*GRID_HEIGHT); 
    u_out = u; 
    v_out = v; 


  end

  logic [NUM_INPUTS-1:0][DATA_WIDTH-1:0] fifo_out; 
  logic [NUM_INPUTS-1:0] fifo_valid_out; 

  logic [DATA_WIDTH-1:0] data_out; 

  assign data_out = fifo_out[current_ix == 0 ? NUM_INPUTS-1 : current_ix - 1]; 
  // assign fifo_valid_out[current_ix == 0 ? NUM_INPUTS-1 : current_ix - 1]; valid_outputs = 

  generate
    genvar i; 
    for(i = 0; i<NUM_INPUTS; i=i+1) begin 
      fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_SLOTS(20)
      )fifo_isnt(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_line(data_line[i]),
        .data_valid_in(valid_array[i]),
        .receiver_ready(current_ix == i), 
        .data_out(fifo_out[i]), 
        .data_valid_out(fifo_valid_out[i]), 
        .full_out()
      );
    end 
  endgenerate
  always_ff @(posedge clk_in) begin
    if(rst_in) begin 
    end else begin 
      if(fifo_valid_out[current_ix == 0 ? NUM_INPUTS-1 : current_ix - 1]) begin 
        valid_outputs[selector] <= 1;
        output_array[selector] <= {new_hcount,new_vcount,u,v,data_out};  
      end 

      for(int i = 0; i<NUM_OUTPUTS; i=i+1) begin 
        if(i != selector) begin 
          valid_outputs[i] <= 0;
        end
      end 
    end 
  end
        
  //       output_array[selector] <= curr_data;
  //       todo[current_ix] <= 0; 
  //       valid_outputs[selector] <= 1; 

  //     end 

  //     for(int i = 0; i<NUM_INPUTS; i=i+1) begin 

        
  //       if(valid_array[i]) begin 
  //         if(i != current_ix) begin
            
  //           stored_values[i] <= data_line[i];
  //         end 
  //         todo[i] <= 1;
          
  //       end
  //     end 
        

  //     end 
  //   end








endmodule