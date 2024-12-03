module video_sig_gen
#(
  parameter ACTIVE_H_PIXELS = 1280,
  parameter H_FRONT_PORCH = 110,
  parameter H_SYNC_WIDTH = 40,
  parameter H_BACK_PORCH = 220,
  parameter ACTIVE_LINES = 720,
  parameter V_FRONT_PORCH = 5,
  parameter V_SYNC_WIDTH = 5,
  parameter V_BACK_PORCH = 20,
  parameter FPS = 60)
(
  input wire pixel_clk_in,
  input wire rst_in,
  output logic [10:0] hcount_out,
  output logic [9:0] vcount_out,
  output logic vs_out, //vertical sync out
  output logic hs_out, //horizontal sync out
  output logic ad_out,
  output logic nf_out, //single cycle enable signal
  output logic [5:0] fc_out); //frame

  localparam TOTAL_PIXELS = (ACTIVE_LINES + V_FRONT_PORCH + V_SYNC_WIDTH + V_BACK_PORCH) * (ACTIVE_H_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH + H_BACK_PORCH); //figure this out
  localparam LINE_WIDTH = (ACTIVE_H_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH + H_BACK_PORCH); 
  localparam TOTAL_LINES = ACTIVE_LINES + V_FRONT_PORCH + V_SYNC_WIDTH + V_BACK_PORCH; //figure this out

  always_comb begin
    if(!rst_in) begin 
      if(hcount_out < ACTIVE_H_PIXELS && vcount_out < ACTIVE_LINES) begin 
        ad_out = 1; 
      end else begin 
        if (hcount_out >= ACTIVE_H_PIXELS && hcount_out < ACTIVE_H_PIXELS + H_FRONT_PORCH ) begin 
          hs_out = 0; 
        end else if(hcount_out >= ACTIVE_H_PIXELS + H_FRONT_PORCH && hcount_out < ACTIVE_H_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH) begin 
          hs_out = 1; 
        end else if(hcount_out >= ACTIVE_H_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH && hcount_out < LINE_WIDTH) begin 
          hs_out = 0; 
        end else begin 
          hs_out = 0; 
        end 

        if (vcount_out >= ACTIVE_LINES && vcount_out < ACTIVE_LINES + V_FRONT_PORCH) begin 
          vs_out = 0; 
        end else if(vcount_out >= ACTIVE_LINES + V_FRONT_PORCH && vcount_out < ACTIVE_LINES + V_FRONT_PORCH + V_SYNC_WIDTH) begin 
          vs_out = 1; 
        end else if(vcount_out >= ACTIVE_LINES + V_FRONT_PORCH + V_SYNC_WIDTH && vcount_out < TOTAL_LINES) begin 
          vs_out = 0; 
        end else begin 
          vs_out = 0; 
        end

        ad_out = 0; 
      end
    end else begin 
      ad_out = 0; 
      hs_out = 0; 
      vs_out = 0; 
    end
  end 

  //your code here
  always_ff @(posedge pixel_clk_in) begin 
    if(rst_in) begin 
      vcount_out <= 0; 
      hcount_out <= 0; 
      nf_out <= 0;
      fc_out <= 0; 
    end else begin
      if(hcount_out == LINE_WIDTH - 1) begin
        hcount_out <= 0; 
        nf_out <= 0; 
        if(vcount_out == TOTAL_LINES - 1) begin 
          vcount_out <= 0;  
        end else begin 
          vcount_out <= vcount_out + 1; 
        end
      end else begin 
        hcount_out <= hcount_out + 1; 
        if(hcount_out == ACTIVE_H_PIXELS - 1 && vcount_out == ACTIVE_LINES) begin
          if(fc_out == FPS - 1) begin 
            fc_out <= 0; 
          end else begin 
            fc_out <= fc_out + 1; 
          end
          nf_out <= 1; 
        end else begin 
          nf_out <= 0; 
        end
      end
    end
  end

endmodule