module fifo
#(
  parameter NUM_SLOTS = 100, 
  parameter DATA_WIDTH = 64, 
  parameter DELAY = 0
)(    input wire clk_in,
      input wire rst_in,
      input wire data_valid_in, 
      input wire receiver_ready, 
      input wire [DATA_WIDTH-1:0] data_line,
      output logic [DATA_WIDTH-1:0] data_out, 
      output logic data_valid_out,
      output logic full_out
);

  logic [$clog2(NUM_SLOTS)-1:0] next_open;
  logic [NUM_SLOTS-1:0] [DATA_WIDTH-1:0] data_store; 
  logic [$clog2(DELAY)-1:0] steps; 
  logic start_count; 
  logic print_out; 

  assign full_out = next_open == NUM_SLOTS; 

  counter step_counter(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .period_in(DELAY),
        .count_out(steps)
  );

  always_ff @(posedge clk_in) begin 
    if(rst_in) begin 
      data_store <= 0; 
      next_open <= 0; 
      data_out <= 0; 
      start_count <= 0; 
    end else begin 

      if(receiver_ready) begin
        if(next_open != 0) begin 
          start_count <= 1; 
          print_out <= 1; 
          if(steps == DELAY - 1 || DELAY == 0) begin 
            data_valid_out <= 1; 
            for(int i = 0; i<NUM_SLOTS; i=i+1) begin 

                if(i == 0) begin 
                  data_out <= data_store[0]; 
                end else begin 
                  data_store[i-1] <= data_store[i];
                end 
                
                next_open <= next_open - 1; 

              end 
          end else begin 
            data_valid_out <= 0;
          end 
        end else begin 
          data_valid_out <= 0;
        end 
      end else begin 
        data_valid_out <= 0; 
      end

      if(data_valid_in) begin 
        if(next_open < NUM_SLOTS) begin 

          next_open <= next_open + 1; 
          data_store[next_open] <= data_line; 
        end
      end 

    end
    
  end 
  
endmodule