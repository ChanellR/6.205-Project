module test_pattern_generator(
  input wire [1:0] sel_in,
  input wire [10:0] hcount_in,
  input wire [9:0] vcount_in,
  output logic [7:0] red_out,
  output logic [7:0] green_out,
  output logic [7:0] blue_out
  );
  //your code here.
  //logic should be purely combinational

  always_comb begin 
    case(sel_in) 
      2'b00: begin
        red_out = 8'h4d;
        green_out = 8'h21;
        blue_out = 8'ha6;
      end
      2'b01: begin 
        if(vcount_in == 360 || hcount_in == 640) begin 
          red_out = 8'hFF; 
          green_out = 8'hFF; 
          blue_out = 8'hFFF; 
        end else begin 
          red_out = 0; 
          green_out = 0; 
          blue_out = 0; 
        end
      end
      2'b10: begin 
        red_out = hcount_in[7:0]; 
        green_out = hcount_in[7:0]; 
        blue_out = hcount_in[7:0]; 
      end
      2'b11: begin 
        red_out = hcount_in[7:0]; 
        green_out = vcount_in[7:0]; 
        blue_out = hcount_in+vcount_in; 
      end
      default: begin 
          red_out = 0; 
          green_out = 0; 
          blue_out = 0; 
      end
    endcase
  end 
endmodule
