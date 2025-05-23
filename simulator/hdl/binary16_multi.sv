module binary16_multi (
    input wire clk_in,
    input wire rst,
    input wire [15:0] a,
    input wire [15:0] b,
    input wire data_valid_in,
    output logic [15:0] result,
    output logic data_valid_out,
    output logic busy
);
    // 3 cycles to compute binary16 multiplication
    // Assuming everything is normalized

    assign busy = |valid_pipe;
    
    localparam stages = 4;
    logic [stages-1:0] valid_pipe;
    always_ff @( posedge clk_in ) begin
        if (rst) begin
            valid_pipe <= 0;
        end else begin
            valid_pipe <= {valid_pipe[stages-2:0], data_valid_in};
        end
    end
    assign data_valid_out = valid_pipe[stages-1];

    // Calculate result sign
    logic [stages-2:0] sign_result_pipe;
    logic [21:0] mant_product, mant_product_pipe; // 11-bit mantissa * 11-bit mantissa = 22-bit mantissa
    logic [4:0] exp_sum, exp_sum_pipe;
    logic [2:0] [4:0] exp_a, exp_b;
    logic [10:0] mant_a, mant_b;
    always_ff @( posedge clk_in ) begin
        if (rst) begin
            sign_result_pipe <= 0;
            exp_a <= 0;
            exp_b <= 0;
            // mant_product <= 0;
            exp_sum <= 0;
            mant_a <= 0;
            mant_b <= 0;
        end else begin
            sign_result_pipe <= {sign_result_pipe[stages-3:0], a[15] ^ b[15]};
            exp_a <= {exp_a[1:0], a[14:10]};
            exp_b <= {exp_b[1:0], b[14:10]};
            mant_a <= {1'b1, a[9:0]};
            mant_b <= {1'b1, b[9:0]};
            // extra normalization is done in the case of multuplying two subnormals
            exp_sum <= (a[14:10] + b[14:10] > 15) ? a[14:10] + b[14:10] - 15 : 5'b0; // Subtract bias
        end
    end

    logic [9:0] mant_result;
    logic [4:0] exp_result;
    always_ff @( posedge clk_in ) begin
        if (rst) begin
            mant_result <= 0;
            exp_result <= 0;
            mant_product <= 0;
            exp_sum_pipe <= 0;
        end else begin
            mant_product <= mant_a * mant_b; // adds one cycle
            exp_sum_pipe <= exp_sum;
            // mant_product_pipe <= mant_product;
            if (mant_product[21]) begin
                mant_result <= mant_product[20:11];
                exp_result <= exp_sum_pipe + 1;
            end else begin
                mant_result <= mant_product[19:10];
                exp_result <= exp_sum_pipe;
            end
        end
    end

    // Handle special cases (zero, infinity, NaN)
    always_ff @( posedge clk_in ) begin
        if (exp_a[2] == 0 || exp_b[2] == 0) begin
            result <= 16'b0; // Zero
        end else if (exp_a[2] == 31 || exp_b[2] == 31) begin
            result <= {sign_result_pipe[stages-2], 5'b11111, 10'b0}; // Infinity
        end else begin
            result <= {sign_result_pipe[stages-2], exp_result, mant_result};
        end
    end

endmodule