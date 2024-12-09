`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module binary16_div_pipelined (
    input wire clk_in,
    input wire rst,
    input wire [15:0] a, // 16-bit binary16 floating-point input a
    input wire [15:0] b, // 16-bit binary16 floating-point input b
    input wire data_valid_in,
    output logic [15:0] result, // 16-bit binary16 floating-point result
    output logic data_valid_out,
    output logic busy
);

    // 24 cycles to compute binary16 division
    // fully pipelined

    // Extract sign, exponent, and mantissa
    logic sign_a, sign_b;
    logic [4:0] exp_a, exp_b;
    logic [10:0] mant_a, mant_b; 

    // Extract fields
    assign sign_a = a[15];
    assign exp_a = a[14:10];
    assign mant_a = {1'b1, a[9:0]}; // Implicit leading 1 for normalized numbers
    
    assign sign_b = b[15];
    assign exp_b = b[14:10];
    assign mant_b = {1'b1, b[9:0]}; // Implicit leading 1 for normalized numbers
    
    // This is a ridiculous amount of bits, maybe I can fit iterations in once cycle to cut it down
    localparam WIDTH = 11 + 11;
    localparam STAGES = 23;

    logic [STAGES-1:0] valid_pipe;
    logic [STAGES-1:0] [4:0] exp_diff; // leaving the extra stage
    logic [STAGES-1:0] sign_result;

    logic  [31:0] p [STAGES-1:0];
    logic  [WIDTH-1:0] dividend [STAGES-1:0];
    logic  [WIDTH-1:0] divisor [STAGES-1:0];

    logic final_sign, final_valid;
    logic [4:0] final_exp;
    logic [9:0] final_mant;

    assign busy = |valid_pipe;

    always_ff @(posedge clk_in)begin
        if (rst) begin
            valid_pipe <= 0;
            data_valid_out <= 0;
            result <= 0;
            // exp_diff <= 0;
            // sign_result <= 0;
            {final_sign, final_valid, final_exp, final_mant} <= 0;
            for (int i=0; i<STAGES; i=i+1)begin
                exp_diff[i] <= 0;
                sign_result[i] <= 0;
                dividend[i] <= 0;
                divisor[i] <= 0;
                p[i] <= 0;
            end
        end else begin
            valid_pipe <= {valid_pipe[STAGES-2:0], data_valid_in};
            if (data_valid_in)begin
                exp_diff[0] <= exp_a - exp_b + 15; // Adjust for bias
                sign_result[0] <= sign_a ^ sign_b;
                dividend[0] <= (mant_a << 11);
                divisor[0] <= mant_b;
                p[0] <= 0;
            end else begin
                exp_diff[0] <= 0;
                sign_result[0] <= 0;
                dividend[0] <= 0;
                divisor[0] <= 0;
                p[0] <= 0;
            end

            for (int i=1; i<STAGES; i=i+1)begin
                exp_diff[i] <= exp_diff[i-1];
                sign_result[i] <= sign_result[i-1];
                if (divisor[i-1] == 0) begin
                    p[i] <= p[i-1];
                    dividend[i] <= dividend[i-1];
                    divisor[i] <= divisor[i-1];
                end else begin
                    if ({p[i-1][WIDTH-2:0],dividend[i-1][WIDTH-1]}>=divisor[i-1][WIDTH-1:0])begin
                        p[i] <= {p[i-1][WIDTH-2:0],dividend[i-1][WIDTH-1]} - divisor[i-1][WIDTH-1:0];
                        dividend[i] <= {dividend[i-1][WIDTH-2:0],1'b1};
                    end else begin
                        p[i] <= {p[i-1][WIDTH-2:0],dividend[i-1][WIDTH-1]};
                        dividend[i] <= {dividend[i-1][WIDTH-2:0],1'b0};
                    end
                    divisor[i] <= divisor[i-1];
                end
            end

            final_valid <= valid_pipe[STAGES-1];
            if (dividend[STAGES-1][11]) begin
                final_sign <= sign_result[STAGES-1];
                final_exp <= exp_diff[STAGES-1];
                final_mant <= dividend[STAGES-1][10:1];
            end else begin
                final_sign <= sign_result[STAGES-1];
                final_exp <= exp_diff[STAGES-1] - 1;
                final_mant <= dividend[STAGES-1][9:0];
            end

            data_valid_out <= final_valid;
            result <= {final_sign, final_exp, final_mant};
        end
    end
endmodule

`default_nettype wire