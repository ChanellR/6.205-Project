module pipelined_mvp 
// "[['1011101110000100', '0000000000000000', '1011010101111000', '0000000000000000'], 
// ['0000000000000000', '0011110000000000', '0000000000000000', '0000000000000000'], 
// ['0011010101111011', '0000000000000000', '1011101110001000', '1101001001001001'], 
// ['0011010101111000', '0000000000000000', '1011101110000100', '1101001001000000']]"
#(
parameter A = 16'b1011101100010000,
parameter B = 16'b0011001011000100,
parameter C = 16'b1011011010110100,
parameter D = 16'b0000000000000000,
parameter E = 16'b0011010100100100,
parameter F = 16'b0011101101100010,
parameter G = 16'b1011001011000100,
parameter H = 16'b0000000000000000,
parameter I = 16'b0011010101111011,
parameter J = 16'b1011010100100111,
parameter K = 16'b1011101100010100,
parameter L = 16'b1100110101001111,
parameter M = 16'b0011010101111000,
parameter N = 16'b1011010100100100,
parameter O = 16'b1011101100010000,
parameter P = 16'b1100110101000000
)(
  input wire clk_in,
  input wire rst_in,
  input wire [15:0] x, 
  input wire [15:0] y, 
  input wire [15:0] z, 
  input wire data_valid_in, 
  output wire [15:0] x_out,
  output wire [15:0] y_out, 
  output wire [15:0] z_out, 
  output wire [15:0] w_out, 
  output wire data_valid_out
);

  //col1 = A E I M 
  //col2 = B F J N 
  //col3 = C G K O 
  //col4 = D H L P 

  logic [63:0] pad_vector_1; 
  logic [63:0] pad_vector_2; 
  logic [63:0] pad_vector_3; 
  logic [63:0] pad_vector_4; 

  assign pad_vector_1 = {x,x,x,x};
  assign pad_vector_2 = {y,y,y,y};
  assign pad_vector_3 = {z,z,z,z};
  assign pad_vector_4 = {16'h3C00,16'h3C00,16'h3C00,16'h3C00}; 

  logic [15:0] [15:0] full_vector; 

  logic [15:0] [15:0] matrix = {A, E, I, M, B, F, J, N, C, G, K, O, D, H, L, P}; 
  assign full_vector = {pad_vector_1, pad_vector_2, pad_vector_3, pad_vector_4}; 
  
  logic [15:0] [15:0] multi_result; 
  logic [15:0] multi_result_valid; 
  logic [3:0][3:0][15:0] structured_multi_result; 

  logic [1:0][3:0][15:0] add_4_result; 
  logic [1:0][3:0] add_4_result_valid; 

  logic [3:0] add_2_result_valid; 

  logic [3:0][15:0] result_vector; 
  
  assign structured_multi_result = multi_result; 
  assign data_valid_out = add_2_result_valid; 

  assign x_out = result_vector[3]; 
  assign y_out = result_vector[2]; 
  assign z_out = result_vector[1]; 
  assign w_out = result_vector[0]; 

  // assign data_valid_out = &screen_coordinates_valid;
  // assign result = screen_coordinates;

  generate
    genvar i;
    for (i=0; i<16; i=i+1) begin

      //v = u1*col1 + u2*col2 + u3*col3 + u4*col4.

      binary16_multi multiply(
        .clk_in(clk_in),
        .rst(rst_in),
        .a(matrix[i]),
        .b(full_vector[i]),
        .data_valid_in(data_valid_in),
        .result(multi_result[i]),
        .data_valid_out(multi_result_valid[i]),
        .busy()
      );

    end 
  endgenerate 

  generate 
    genvar j; 
    for (j=0; j<4; j=j+1) begin
      //col1+col2 
      //col3+col4 
      binary16_adder add_4_0(
        .clk_in(clk_in),
        .rst(rst_in),
        .a(structured_multi_result[0][j]),
        .b(structured_multi_result[1][j]),
        .data_valid_in(multi_result_valid[j]),
        .result(add_4_result[0][j]),
        .data_valid_out(add_4_result_valid[0][j]),
        .busy()
      );
      binary16_adder add_4_1(
        .clk_in(clk_in),
        .rst(rst_in),
        .a(structured_multi_result[2][j]),
        .b(structured_multi_result[3][j]),
        .data_valid_in(multi_result_valid[j]),
        .result(add_4_result[1][j]),
        .data_valid_out(add_4_result_valid[1][j]),
        .busy()
      );

      //(col1+col2)+(col3+col4)
      binary16_adder add_2_0(
        .clk_in(clk_in),
        .rst(rst_in),
        .a(add_4_result[0][j]),
        .b(add_4_result[1][j]),
        .data_valid_in(add_4_result_valid[0][j]),
        .result(result_vector[j]),
        .data_valid_out(add_2_result_valid[j]),
        .busy()
      );

    end 
  endgenerate 


endmodule 

