module arbiter 
#(
  parameter NUM_INPUTS = 4,
  parameter DATA_WIDTH = 64
)(
  input wire clk_in, 
  input wire rst_in, 
  input wire [NUM_INPUTS-1:0] [DATA_WIDTH-1:0] data_line,
  input wire [NUM_INPUTS-1:0] valid_array, 
  output logic [DATA_WIDTH-1:0] data_out, 
  output logic data_valid_out
);

  logic [NUM_INPUTS-1:0] [DATA_WIDTH-1:0] stored_values; 
  logic [NUM_INPUTS-1:0] todo;
  logic [$clog2(NUM_INPUTS)-1:0] current_ix; 


  counter cycles(.clk_in(clk_in),
                .rst_in(rst_in),
                .period_in(NUM_INPUTS),
                .count_out(current_ix)
  );

  logic [NUM_INPUTS-1:0][DATA_WIDTH-1:0] fifo_out; 
  logic [NUM_INPUTS-1:0] fifo_valid_out; 

  assign data_out = fifo_out[current_ix == 0 ? NUM_INPUTS-1 : current_ix - 1]; 
  assign data_valid_out = fifo_valid_out[current_ix == 0 ? NUM_INPUTS-1 : current_ix-1]; 

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

    // always_ff @(posedge clk_in) begin
    //   if(rst_in) begin 
    //     stored_values <= 0; 
    //     data_valid_out <= 0; 
    //   end
    // end

  // always_ff @(posedge clk_in) begin
  //   if(rst_in) begin 
  //     todo <= 0; 
  //     stored_values <= 0; 
  //   end else begin 
  //     if(todo[current_ix]) begin 
        
  //       data_out <= stored_values[current_ix];
  //       stored_values[current_ix] <= 0; 
  //       todo[current_ix] <= 0; 
  //       data_valid_out <= 1; 

  //     end else begin 

  //       data_valid_out <= 0; 

  //     end 

  //     for(int i = 0; i<NUM_INPUTS; i=i+1) begin 

        
  //       if(valid_array[i]) begin 
  //         if(i != current_ix) begin
  //           todo[i] <= 1;
  //           stored_values[i] <= data_line[i];
  //         end 
          
  //       end
  //   end 
  //   end 
  // end




endmodule