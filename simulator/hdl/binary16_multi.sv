module binary16_multi (
    input logic clk_in,
    input logic rst,
    input logic [15:0] a,
    input logic [15:0] b,
    input logic data_valid_in,
    output logic [15:0] result,
    output logic data_valid_out
);
    // 3 cycles to compute binary16 multiplication
    // Assuming everything is normalized

    // Extract sign, exponent, and mantissa
    logic sign_a, sign_b, sign_result;
    logic [4:0] exp_a, exp_b, exp_result;
    logic [10:0] mant_a, mant_b; 
    logic [9:0] mant_result;

    assign sign_a = a[15];
    assign sign_b = b[15];
    assign exp_a = a[14:10];
    assign exp_b = b[14:10];
    assign mant_a = {1'b1, a[9:0]}; // Implicit leading 1
    assign mant_b = {1'b1, b[9:0]}; // Implicit leading 1

    localparam stages = 3;
    logic [stages-1:0] valid_pipe;
    always_ff @( posedge clk_in ) begin
        if (rst) begin
            valid_pipe <= 6'b0;
        end else begin
            valid_pipe <= {valid_pipe[stages-1:0], data_valid_in};
        end
    end
    assign data_valid_out = valid_pipe[stages-1];

    // Calculate result sign
    assign sign_result = sign_a ^ sign_b;
    
    logic [21:0] mant_product; // 11-bit mantissa * 11-bit mantissa = 22-bit mantissa
    logic [4:0] exp_sum;

    always_ff @( posedge clk_in ) begin
        mant_product <= mant_a * mant_b;
        exp_sum <= exp_a + exp_b - 15; // Subtract bias
    end

    always_ff @( posedge clk_in ) begin
        if (mant_product[21]) begin
            mant_result = mant_product[20:11];
            exp_result = exp_sum + 1;
        end else begin
            mant_result = mant_product[19:10];
            exp_result = exp_sum;
        end
    end

    // Handle special cases (zero, infinity, NaN)
    always_ff @( posedge clk_in ) begin
        if (exp_a == 0 || exp_b == 0) begin
            result = 16'b0; // Zero
        end else if (exp_a == 31 || exp_b == 31) begin
            result = {sign_result, 5'b11111, 10'b0}; // Infinity
        end else begin
            result = {sign_result, exp_result, mant_result};
        end
    end

endmodule