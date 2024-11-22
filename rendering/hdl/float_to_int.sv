module float_to_int (
  input wire [15:0] f_value, 
  output logic [15:0] int_value
);

  logic sign; 
  logic [4:0] exponent; 
  logic [9:0] mantissa; 

always_comb begin
    sign = f_value[15];               // Extract sign bit
    exponent = f_value[14:10];        // Extract exponent
    mantissa = f_value[9:0];          // Extract mantissa
    
    if (exponent == 5'b00000) begin  // Subnormal case
        int_value = (sign ? -1 : 1) * (mantissa) >> 10;  // Subnormal: exponent = -14
    end else begin  // Normalized case
        int_value = (sign ? -1 : 1) * (1 << (exponent - 5'd15)) * (1024 + mantissa) >> 10;
    end

end

endmodule 
