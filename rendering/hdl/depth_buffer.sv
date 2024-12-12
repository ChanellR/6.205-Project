
`ifdef SYNTHESIS
`define FPATH(X) `"X`"
`else /* ! SYNTHESIS */
`define FPATH(X) `"../../data/X`"
`endif  /* ! SYNTHESIS */

module depth_buffer 
#(
  DATA_WIDTH = 16, 
  PARTITIONS = 16, 
  SIZE = 3600
)(
  input wire clk_in, 
  input wire rst_in, 
  input wire data_valid_in, 
  input  wire [DATA_WIDTH-1:0] data_in, 
  input wire [31:0] addr_in, 
  output logic comp_out, 
  output logic [DATA_WIDTH-1:0] depth_out, 
  output logic [31:0] addr_out, 
  output logic ready
);
  //BRAM 
  typedef enum {IDLE, COMPARE, WRITING} db_state;
  db_state state; 

  // blk_mem_gen_0 frame_buffer_2 (
  //   .addra(clearing_frame2 ? clear_addr2 : addr_out), //pixels are stored using this math
  //   .clka(clk_pixel),
  //   .wea((new_pixel_out && write_frame_2) || clearing_frame2),
  //   .dina(clearing_frame2 ? 0 : color_out),
  //   .ena(1'b1),
  //   .douta(), //never read from this side
  //   .addrb(addrb),//transformed lookup pixel
  //   .dinb(16'b0),
  //   .clkb(clk_pixel),
  //   .web(1'b0),
  //   .enb(1'b1),
  //   .doutb(frame_buff_raw_2)
  // );
  // The following is an instantiation template for xilinx_true_dual_port_read_first_2_clock_ram

  //  Xilinx True Dual Port RAM, Read First, Dual Clock

  logic [DATA_WIDTH-1:0] buffer_out; 
  logic [DATA_WIDTH-1:0] curr_data; 
  logic [31:0] curr_addr; 
  logic done; 
  logic write_enable; 

  xilinx_true_dual_port_read_first_2_clock_ram #(
    .RAM_WIDTH(6),                       // Specify RAM data width
    .RAM_DEPTH(3600),                     // Specify RAM depth (number of entries)
    .RAM_PERFORMANCE("HIGH_PERFORMANCE"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY"
    .INIT_FILE("fb.mem")                        // Specify name/location of RAM initialization file if using one (leave blank if not)
  ) your_instance_name (
    .addra(addr_in),   // Port A address bus, width determined from RAM_DEPTH
    .addrb(addr_in),   // Port B address bus, width determined from RAM_DEPTH
    .dina(curr_data),     // Port A RAM input data, width determined from RAM_WIDTH
    .dinb(),     // Port B RAM input data, width determined from RAM_WIDTH
    .clka(clk_in),     // Port A clock
    .clkb(clk_in),     // Port B clock
    .wea(write_enable),       // Port A write enable
    .web(1'b0),       // Port B write enable
    .ena(1'b1),       // Port A RAM Enable, for additional power savings, disable port when not in use
    .enb(1'b1),       // Port B RAM Enable, for additional power savings, disable port when not in use
    .rsta(rst_in),     // Port A output reset (does not affect memory contents)
    .rstb(rst_in),     // Port B output reset (does not affect memory contents)
    .regcea(1'b1), // Port A output register enable
    .regceb(1'b1), // Port B output register enable
    .douta(),   // Port A RAM output data, width determined from RAM_WIDTH
    .doutb(buffer_out)    // Port B RAM output data, width determined from RAM_WIDTH
  );



  always_ff @(posedge clk_in) begin 
    if(rst_in) begin 
      curr_addr <= 0; 
      addr_out <= 0; 
      write_enable<=0; 
    end else begin
      case(state) 
        IDLE: begin 
          ready <= 1; 
          write_enable <= 0; 
          comp_out <= 0; 
          depth_out <= 0; 
          addr_out <= 0; 
          if(data_valid_in) begin 
            state <= COMPARE; 
            curr_data <= data_in; 
            curr_addr <= addr_in; 
            ready <= 0; 
          end 
        end

        COMPARE: begin 
          done <= 1; 
          if(done) begin 
            state <= WRITING; 
            done <= 0; 
            comp_out <= buffer_out > curr_data; 
            depth_out <= curr_data; 
            addr_out <= curr_addr; 
          end 
        end

        WRITING: begin 
          if(comp_out) begin 
            write_enable <= 1; 
          end
          state <= IDLE; 
          
        end 

      endcase  
    end 
   
  end 

endmodule