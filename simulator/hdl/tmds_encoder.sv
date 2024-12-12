`timescale 1ns / 1ps
`default_nettype none // prevents system from inferring an undeclared logic (good practice)
 
module tmds_encoder(
  input wire clk_in,
  input wire rst_in,
  input wire [7:0] data_in,  // video data (red, green or blue)
  input wire [1:0] control_in, //for blue set to {vs,hs}, else will be 0
  input wire ve_in,  // video data enable, to choose between control or video signal
  output logic [9:0] tmds_out
);
 
  logic [8:0] q_m;
  logic [4:0] cnt; 
  logic [3:0] n_1; 
   
  tm_choice mtm(
    .data_in(data_in),
    .qm_out(q_m));

  assign n_1 = (q_m[0] + q_m[1] + q_m[2] + q_m[3] + q_m[4] + q_m[5] + q_m[6] + q_m[7]);
 
  //your code here.
  always_ff @(posedge clk_in) begin 
    if(rst_in) begin 
        cnt <= 0; 
        // n_1 <= 0; 
        tmds_out <=0; 
    end else begin 
        if(!ve_in) begin 
            cnt <= 0; 
            case(control_in)
                2'b00: tmds_out <= 10'b1101010100;
                2'b01: tmds_out <= 10'b0010101011;
                2'b10: tmds_out <= 10'b0101010100;
                2'b11: tmds_out <= 10'b1010101011;
                default: tmds_out <= 10'b0;
            endcase
        end else begin 

             // number of 1s 
            if(n_1 == 4 || cnt == 0) begin 

                tmds_out[9] <= ~q_m[8];
                tmds_out[8] <= q_m[8];
                tmds_out[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];

                if(q_m[8] == 0) begin
                    cnt <= cnt + (8 - n_1) - n_1; 
                end else begin 
                    cnt <= cnt + n_1 - (8 - n_1); 
                end  

            end else begin
                if((cnt[4] == 0 && n_1 > 4) || (cnt[4] == 1 && n_1 < 4)) begin 
                    tmds_out[9] <= 1; 
                    tmds_out[8] <= q_m[8]; 
                    tmds_out[7:0] <= ~q_m[7:0]; 
                    cnt <= cnt + (q_m[8] << 1) + ((8-n_1) - n_1);
                end else begin 
                    // careful
                    tmds_out[9] <= 0; 
                    tmds_out[8] <= q_m[8]; 
                    tmds_out[7:0] <= q_m[7:0]; 
                    cnt <= cnt - ((q_m[8] == 0 ? 1 : 0) << 1) + (n_1 - (8-n_1));
                end
            end

        end
    end 
  end

 
endmodule
 
`default_nettype wire