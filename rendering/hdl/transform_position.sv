module transform_position #(
  parameter DIMS = 2,
  parameter TWICE_BOUNDS = 32'h4c004c00, // (8*2, 8*2)
  parameter SCREEN_BOUNDS = 32'h5D0059A0, // (320, 180)
  parameter HALF_SCREEN_BOUNDS = 32'h590055A0 // (320/2, 180/2)
) (
  input wire clk_in,
  input wire rst,
  input wire [DIMS-1:0] [15:0] f, 
  input wire data_valid_in,
  output logic [DIMS-1:0] [31:0] result,
  output logic data_valid_out
);

  logic [DIMS-1:0] [15:0] position_ratio_result, relative_position_result, normalized_position_result; 
  logic [DIMS-1:0] position_ratio_valid, relative_position_valid, normalized_position_valid, screen_coordinates_valid;
  logic [DIMS-1:0] [31:0] screen_coordinates;

  assign data_valid_out = &screen_coordinates_valid;
  assign result = screen_coordinates;

  generate
    genvar i;
    for (i=0; i<DIMS; i=i+1) begin
      binary16_div_pipelined screen_ratio(
        .clk_in(clk_in),
        .rst(rst),
        .a(f[i]),
        .b(TWICE_BOUNDS[(i+1)*16-1:i*16]),
        .data_valid_in(data_valid_in),
        .result(position_ratio_result[i]),
        .data_valid_out(position_ratio_valid[i]),
        .busy()
      );
      binary16_multi relative_pos(
        .clk_in(clk_in),
        .rst(rst),
        .a(position_ratio_result[i]),
        .b(SCREEN_BOUNDS[(i+1)*16-1:i*16]),
        .data_valid_in(position_ratio_valid[i]),
        .result(relative_position_result[i]),
        .data_valid_out(relative_position_valid[i]),
        .busy()
      );
      binary16_adder normalized_pos(
        .clk_in(clk_in),
        .rst(rst),
        .a(relative_position_result[i]),
        .b(HALF_SCREEN_BOUNDS[(i+1)*16-1:i*16]),
        .data_valid_in(relative_position_valid[i]),
        .result(normalized_position_result[i]),
        .data_valid_out(normalized_position_valid[i]),
        .busy()
      );
      truncate_float trunc_pos(
        .clk_in(clk_in),
        .rst(rst),
        .f(normalized_position_result[i]),
        .data_valid_in(normalized_position_valid[i]),
        .result(screen_coordinates[i]),
        .data_valid_out(screen_coordinates_valid[i])
      );
    end
  endgenerate

endmodule 
