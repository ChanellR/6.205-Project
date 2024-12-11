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
  output logic [$clog2(TOTAL_PIXELS)-1:0] hcount_out,
  output logic [$clog2(TOTAL_LINES)-1:0] vcount_out,
  output logic vs_out, //vertical sync out
  output logic hs_out, //horizontal sync out
  output logic ad_out,
  output logic nf_out, //single cycle enable signal
  output logic [5:0] fc_out); //frame

  localparam TOTAL_PIXELS = (ACTIVE_H_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH + H_BACK_PORCH); 
  localparam TOTAL_LINES = (ACTIVE_LINES + V_FRONT_PORCH + V_SYNC_WIDTH + V_BACK_PORCH);

  logic [$clog2(TOTAL_PIXELS)-1:0] hcount;
  logic [$clog2(TOTAL_LINES)-1:0] vcount;

  always_ff @( posedge pixel_clk_in ) begin : driver

    if (nf_out) begin
      nf_out <= 0;
    end
    
    if (rst_in) begin
      
      hcount <= 0;
      vcount <= 0;

      nf_out <= 0;
      fc_out <= 0; // frame 0

    end else begin
      
      // counting logic 
      if (hcount == TOTAL_PIXELS - 1) begin
        hcount <= 0;
        if (vcount == TOTAL_LINES - 1) begin
          vcount <= 0;
        end else begin
          vcount <= vcount + 1;
        end
      end else begin
        hcount <= hcount + 1;
      end

      if ((hcount == ACTIVE_H_PIXELS - 1) && (vcount == ACTIVE_LINES)) begin
        nf_out <= 1;
        if (fc_out == FPS - 1) begin
          fc_out <= 0;
        end else begin
          fc_out <= fc_out + 1;
        end
      end
      
    end

  end

  always_comb begin : output_logic
    hcount_out = hcount;
    vcount_out = vcount;
    ad_out = (hcount < ACTIVE_H_PIXELS) && (vcount < ACTIVE_LINES) && (!rst_in);
    hs_out = (hcount >= ACTIVE_H_PIXELS + H_FRONT_PORCH) && (hcount < ACTIVE_H_PIXELS + H_FRONT_PORCH + H_SYNC_WIDTH);
    vs_out = (vcount >= ACTIVE_LINES + V_FRONT_PORCH) && (vcount < ACTIVE_LINES + V_FRONT_PORCH + V_SYNC_WIDTH);
  end

endmodule
