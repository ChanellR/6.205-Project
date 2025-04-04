`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module binary16_adder (
    input wire clk_in,
    input wire rst,
    input wire [15:0] a,
    input wire [15:0] b,
    input wire data_valid_in,
    output logic [15:0] result,
    output logic data_valid_out,
    output logic busy
);
    // 6 cycles to compute binary16 addition
    // Good resource on floating-point: https://pages.cs.wisc.edu/~markhill/cs354/Fall2008/notes/arith.flpt.html
    // Assuming everything is normalized, and non zero

    // Internal signals
    logic [4:0] exp_a, exp_b, exp_max, exp_diff, exp_sum;
    logic [10:0] mant_a, mant_b, mant_sum;
    logic sign_a, sign_b, sign_sum;
    logic [11:0] aligned_mant_a, aligned_mant_b;
    logic [12:0] mant_sum_ext;
    logic [4:0] exp_sum_adj;
    logic [10:0] mant_sum_norm;
    logic [4:0] leading_zeros;
    
    // Extract fields
    assign sign_a = a[15];
    assign exp_a = a[14:10];
    assign mant_a = {1'b1, a[9:0]}; // Implicit leading 1 for normalized numbers

    assign sign_b = b[15];
    assign exp_b = b[14:10];
    assign mant_b = {1'b1, b[9:0]}; // Implicit leading 1 for normalized numbers
    
    localparam stages = 4;
    logic [stages-1:0] valid_pipe;
    always_ff @( posedge clk_in ) begin
        if (rst) begin
            valid_pipe <= 6'b0;
        end else begin
            valid_pipe <= {valid_pipe[stages-1:0], data_valid_in};
        end
    end
    assign data_valid_out = valid_pipe[stages-1];
    assign busy = |valid_pipe;
    
    logic sign_a_store, sign_b_store;
    assign exp_diff = (exp_a > exp_b) ? (exp_a - exp_b) : (exp_b - exp_a);
    // Align exponents
    always_ff @( posedge clk_in ) begin
        exp_max <= (exp_a > exp_b) ? exp_a : exp_b;
        if (a[14:0] == 15'b0) begin
            aligned_mant_a <= 0;
        end else begin
            aligned_mant_a <= (exp_a > exp_b) ? mant_a : (mant_a >> exp_diff);
        end
        if (b[14:0] == 15'b0) begin
            aligned_mant_b <= 0;
        end else begin
            aligned_mant_b <= (exp_b > exp_a) ? mant_b : (mant_b >> exp_diff);
        end
        // aligned_mant_b <= (exp_b > exp_a) ? mant_b : (mant_b >> exp_diff);
        sign_a_store <= sign_a;
        sign_b_store <= sign_b;        
    end

    logic [4:0] exp_max_store;
    // Add/subtract significands
    always_ff @( posedge clk_in ) begin
        exp_max_store <= exp_max;
        if (sign_a_store == sign_b_store) begin
            mant_sum_ext <= aligned_mant_a + aligned_mant_b;
            sign_sum <= sign_a_store;
        end else if (aligned_mant_a == aligned_mant_b) begin
            // If exps and mantissas are equal, and signs are different, result is 0
            mant_sum_ext <= 0; 
            exp_max_store <= 0;
            sign_sum <= 1'b0;
        end else if (aligned_mant_a > aligned_mant_b) begin
            mant_sum_ext <= aligned_mant_a - aligned_mant_b;
            sign_sum <= sign_a_store;
        end else begin
            mant_sum_ext <= aligned_mant_b - aligned_mant_a;
            sign_sum <= sign_b_store;
        end
    end

    logic sign_sum_store;
    // Normalize result
    always_ff @( posedge clk_in ) begin
        sign_sum_store <= sign_sum;
        if (mant_sum_ext[11]) begin
            mant_sum_norm <= mant_sum_ext[11:1];
            exp_sum_adj <= exp_max_store + 1;
        end else begin
            mant_sum_norm <= mant_sum_ext[10:0];
            exp_sum_adj <= exp_max_store;
        end
    end

    // TODO: This module might kill timing
    // Count leading zeros
    // always_ff @( posedge clk_in ) begin
    assign leading_zeros = (mant_sum_norm == 0) ? 0 :
                (mant_sum_norm[10] == 1'b1) ? 0 :
                (mant_sum_norm[9] == 1'b1) ? 1 :
                (mant_sum_norm[8] == 1'b1) ? 2 :
                (mant_sum_norm[7] == 1'b1) ? 3 :
                (mant_sum_norm[6] == 1'b1) ? 4 :
                (mant_sum_norm[5] == 1'b1) ? 5 :
                (mant_sum_norm[4] == 1'b1) ? 6 :
                (mant_sum_norm[3] == 1'b1) ? 7 :
                (mant_sum_norm[2] == 1'b1) ? 8 :
                (mant_sum_norm[1] == 1'b1) ? 9 :
                (mant_sum_norm[0] == 1'b1) ? 10 : 11;
    // end

    logic sign_final;
    // Adjust exponent and significand
    always_ff @( posedge clk_in ) begin
        sign_final <= sign_sum_store;
        exp_sum <= exp_sum_adj - leading_zeros;
        mant_sum <= mant_sum_norm << leading_zeros;
    end

    // Assemble result
    assign result = (data_valid_out) ? {sign_final, exp_sum, mant_sum[9:0]} : 16'b0;

endmodule

`default_nettype wire