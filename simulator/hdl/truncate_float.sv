module truncate_float (
  input wire clk_in,
  input wire rst,
  input wire [15:0] f, 
  input wire data_valid_in,
  output logic [31:0] result,
  output logic data_valid_out
);

  always_ff @( posedge clk_in ) begin 
    if (rst) begin 
      result <= 16'b0;
      data_valid_out <= 1'b0;
    end else begin 
      data_valid_out <= data_valid_in;
      if (f[14:10] == 5'b00000) begin 
        result <= 0; // (f[15] ? -1 : 1) * (f[9:0]) >> 10;
      end else begin 
        // assume positive and > 0
        result <= ({1'b1, f[9:0]} << (f[14:10] - 5'd15)) >> 10;
      end
    end
  end

endmodule 
