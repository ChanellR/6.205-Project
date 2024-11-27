module pixel_manager 
  (
  input wire clk_in, 
  input wire rst_in, 
  input wire [10:0] hcount_in, 
  input wire [9:0] vcount_in, 
  input wire data_valid_in, 
  output logic [15:0] addr_out, 
  output logic [15:0] color_out, 
  output logic data_valid_out
);

  always_ff @(posedge clk_in) begin 

    if(rst_in) begin 
    end else begin 
      if(data_valid_in) begin 
        data_valid_out <= 1;  
        color_out <= 16'b0000_0000_0001_1111; 
        addr_out <= hcount_in + (vcount_in * 320);
      end else begin 
        data_valid_out <= 0; 
      end 
    end 

  end 

endmodule 
