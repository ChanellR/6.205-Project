`default_nettype none
module evt_counter
  ( input wire          clk_in,
    input wire          rst_in,
    input wire          evt_in,
    output logic[15:0]  count_out
  );

  initial begin
    count_out <= 16'b0;
  end
  
  always_ff @(posedge clk_in) begin
    if (rst_in) begin
      count_out <= 16'b0;
    end else if (evt_in) begin
      count_out <= count_out + 1;
    end
  end
endmodule
`default_nettype wire