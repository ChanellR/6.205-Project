module binary16_sqrt (
    input logic clk_in,
    input logic rst,
    input logic [15:0] n,
    input logic data_valid_in,
    output logic [15:0] result,
    output logic data_valid_out
);

    // Takes 13 cycles to compute binary16 sqrt
    // Assumes postive input

    logic [21:0] x, c; //adding 10 precision bits
    logic [20:0] d;
    enum {IDLE, RESIZING, ACTIVE} state;
    
    // Define the floating-point format 
    // logic [4:0] cycle_count;
    logic [4:0] exp;
    logic odd_exp;

    always_ff @( posedge clk_in ) begin 
        if (rst) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    data_valid_out <= 0;
                    if (data_valid_in) begin
                        if (n[14:10] & 1'b1) begin
                            // incase information will be lost on right shift
                            // add 1 to exponent and shift right mantissa
                            exp <= ((n[14:10] + 1) >> 1) + 7;
                            x <= {1'b1, n[9:0]} << 10; // 10 precision bits
                            odd_exp <= 1;
                        end else begin
                            exp <= (n[14:10] >> 1) + 7;
                            x <= {1'b1, n[9:0]} << 11;
                            odd_exp <= 0;
                        end
                        c <= 0;
                        d <= 1 << 20;
                        state <= ACTIVE;
                        // cycle_count <= 1;
                    end
                end 
                RESIZING: begin
                    if (d > x) begin
                        d <= d >> 2;
                    end else begin
                        state <= ACTIVE;
                    end
                    // cycle_count <= cycle_count + 1;
                end
                ACTIVE: begin
                    // https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Binary_numeral_system_(base_2)
                    if (d != 0) begin
                        if (x >= c + d) begin
                            x <= x - (c + d);
                            c <= (c >> 1) + d;
                        end else begin
                            c <= c >> 1;
                        end
                        d <= d >> 2;
                    end else begin
                        result <= {1'b0, exp, c[9:0]};
                        data_valid_out <= 1;
                        state <= IDLE;
                    end
                    // cycle_count <= cycle_count + 1;
                end
                default: state <= IDLE; 
            endcase
        end
    end

endmodule