module bus_driver 
#(
  parameter NUM_OUTPUTS = 4,
  parameter DATA_WIDTH = 6
)(
  input wire clk_in, 
  input wire rst_in, 
  input wire data_valid_in, 
  input wire [DATA_WIDTH-1:0] data_line,
  output logic [NUM_OUTPUTS-1:0] [DATA_WIDTH-1:0] output_array, 
  output logic [NUM_OUTPUTS-1:0] valid_outputs, 
  output logic ix_out
);

  logic [$clog2(NUM_OUTPUTS)-1:0] current_ix; 
  assign ix_out = current_ix; 

  always_ff @(posedge clk_in) begin

    if(rst_in) begin 
      output_array <= 0; 
      valid_outputs <= 0; 
      current_ix <= 0; 
    end else begin 
      if(data_valid_in) begin 
        current_ix <= current_ix + 1; 
        output_array[current_ix] <= data_line; 
        valid_outputs[current_ix] <= 1; 
      end

      for(int i = 0; i< NUM_OUTPUTS; i=i+1) begin 
        if(valid_outputs[i]) begin 
          valid_outputs[i] <= 0; 
        end
      end 

    end 


  end

endmodule