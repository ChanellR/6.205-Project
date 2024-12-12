`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module binary16_div (
    input wire clk_in,
    input wire rst,
    input wire [15:0] a, // 16-bit binary16 floating-point input a
    input wire [15:0] b, // 16-bit binary16 floating-point input b
    input wire data_valid_in,
    output logic [15:0] result, // 16-bit binary16 floating-point result
    output logic data_valid_out
);
    // 24 cycles to compute binary16 division

    // Extract sign, exponent, and mantissa
    logic sign_a, sign_b, sign_result;
    logic [4:0] exp_a, exp_b, exp_result;
    logic [10:0] mant_a, mant_b; 
    logic [9:0] mant_result;

    // Extract fields
    assign sign_a = a[15];
    assign exp_a = a[14:10];
    assign mant_a = {1'b1, a[9:0]}; // Implicit leading 1 for normalized numbers
    
    assign sign_b = b[15];
    assign exp_b = b[14:10];
    assign mant_b = {1'b1, b[9:0]}; // Implicit leading 1 for normalized numbers
    
    localparam WIDTH = 11 + 11;
    logic [WIDTH-1:0] quotient, dividend;
    logic [WIDTH-1:0] divisor;
    logic [5:0] bits_left;
    // logic [5:0] cycle_count;
    logic [5:0] exp_diff;
    logic [31:0] p;

    enum {IDLE, DIVIDING, NORMALIZING} state;
    always_ff @( posedge clk_in ) begin 
        if (rst) begin
            quotient <= 0;
            dividend <= 0;
            divisor <= 0;
            // cycle_count <= 0;
            sign_result <= 0;
            mant_result <= 0;
            exp_result <= 0;
            data_valid_out <= 0;
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (data_valid_in) begin
                        exp_diff <= exp_a - exp_b + 15; // Adjust for bias
                        sign_result <= sign_a ^ sign_b;
                        quotient <= 0;
                        dividend <= (mant_a << 11);
                        divisor <= mant_b;
                        bits_left <= WIDTH-1;
                        p <= 0;
                        // cycle_count <= 1;
                        state <= DIVIDING;
                    end
                    data_valid_out <= 0;
                end 
                DIVIDING: begin
                    if (bits_left == 0) begin
                        if ({p[WIDTH-2:0], dividend[WIDTH-1]} >= divisor[WIDTH-1:0]) begin
                            quotient <= {dividend[WIDTH-2:0], 1'b1};
                        end else begin
                            quotient <= {dividend[WIDTH-2:0], 1'b0};
                        end
                        state <= NORMALIZING;
                    end else begin
                        if ({p[WIDTH-2:0], dividend[WIDTH-1]} >= divisor[WIDTH-1:0]) begin
                            p <= {p[WIDTH-2:0], dividend[WIDTH-1]} - divisor[WIDTH-1:0];
                            dividend <= {dividend[WIDTH-2:0], 1'b1};
                        end else begin
                            p <= {p[WIDTH-2:0], dividend[WIDTH-1]};
                            dividend <= {dividend[WIDTH-2:0], 1'b0};
                        end
                        bits_left <= bits_left - 1;
                    end
                    // // cycle_count <= cycle_count + 1;
                end
                NORMALIZING: begin
                    if (quotient[11]) begin
                        mant_result <= quotient[10:1];
                        exp_result <= exp_diff;
                    end else begin
                        mant_result <= quotient[9:0];
                        exp_result <= exp_diff - 1;
                    end
                    // // cycle_count <= cycle_count + 1;
                    state <= IDLE;
                    data_valid_out <= 1;  
                end
                default: state <= IDLE; 
            endcase
        end
    end

    // Assemble result
    assign result = {sign_result, exp_result, mant_result};

endmodule

`default_nettype wire