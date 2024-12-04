module float_to_int (
  input wire clk_in, 
  input wire rst_in, 
  input wire data_valid_in, 
  input wire [15:0] f_value, 
  output logic [15:0] int_value, 
  output logic data_valid_out
);

  logic sign; 
  logic [4:0] exponent; 
  logic [9:0] mantissa; 

always_comb begin 
  sign = f_value[15];               // Extract sign bit
  exponent = f_value[14:10];        // Extract exponent
  mantissa = f_value[9:0];          // Extract mantissa
end

always_ff @(posedge clk_in) begin
  if(rst_in) begin 
    int_value <= 0; 
  end else begin 
    if(data_valid_in) begin 
    //   if (exponent == 5'b00000) begin  // Subnormal case
    //       int_value <= (mantissa) >> 10;  // Subnormal: exponent = -14
    //   end else begin  // Normalized case
    //       int_value <= (1 << (exponent - 5'd15)) * (1024 + mantissa) >> 10;
    //   end
    // end
      int_value <= (1 << (exponent - 5'd15)) * (1024 + mantissa) >> 10; 
      data_valid_out <= 1; 
    end else begin 
      data_valid_out <= 0; 
    end 
    // int_value <= 2; 
  end
end

// always_comb begin 
//     // if (exponent == 5'b00000) begin  // Subnormal case
//     //     int_value = (mantissa) >> 10;  // Subnormal: exponent = -14
//     // end else begin  // Normalized case
//     //     int_value = (1 << (exponent - 5'd15)) * (1024 + mantissa) >> 10;
//     // end
//   int_value = (1 << (exponent - 5'd15)) * (1024 + mantissa) >> 10;
// end



endmodule 
