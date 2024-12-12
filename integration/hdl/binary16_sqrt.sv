`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module binary16_sqrt (
    input wire clk_in,
    input wire rst,
    input wire [15:0] n,
    input wire data_valid_in,
    output logic [15:0] result,
    output logic data_valid_out,
    output logic busy
);

    // Takes 13 cycles to compute binary16 sqrt
    //  fully pipelined
    // will return 0 if n is negative

    // Define the floating-point format 
    logic [11:0] [21:0] x, c; //adding 10 precision bits
    logic [11:0] [20:0] d;
    logic [11:0] [4:0] exp;
    logic [11:0] valid_pipe;
    logic [11:0] done;
    
    assign busy = |valid_pipe;

    always_ff @( posedge clk_in ) begin
        if (rst) begin
            {x, c, d, exp} <= 0;
            valid_pipe <= 0;
            done <= 0;
        end else begin
            valid_pipe <= {valid_pipe[10:0], data_valid_in};
            if (data_valid_in && !n[15]) begin // if n is positive
                if (n[14:10] & 1'b1) begin
                    // incase information will be lost on right shift
                    // add 1 to exponent and shift right mantissa
                    exp[0] <= ((n[14:10] + 1) >> 1) + 7;
                    x[0] <= ({1'b1, n[9:0]} + 1) << 10; // 10 precision bits
                end else begin
                    if (n == 16'b0) begin
                        exp[0] <= 0;
                        x[0] <= 0;
                        c[0] <= 0;
                        d[0] <= 0;
                    end else begin
                        exp[0] <= (n[14:10] >> 1) + 7;
                        x[0] <= {1'b1, n[9:0]} << 11;
                    end
                end
                
                c[0] <= 0;
                done[0] <= 0;
                d[0] <= 1 << 20;
            end else begin
                exp[0] <= 0;
                x[0] <= 0;
                c[0] <= 0;
                d[0] <= 0;
            end

            for (int i = 1; i < 12; i++) begin
                // the 4.0, 16.0 bug is because c differs by 1, and doesn't overflow
                // https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Binary_numeral_system_(base_2)
                if (d[i-1] != 0) begin
                    if (x[i-1] > d[i-1] && x[i-1] >= c[i-1] + d[i-1]) begin
                        x[i] <= x[i-1] - (c[i-1] + d[i-1]);
                        c[i] <= (c[i-1] >> 1) + d[i-1];
                    end else begin
                        x[i] <= x[i-1];
                        c[i] <= c[i-1] >> 1;
                    end
                    d[i] <= d[i-1] >> 2;
                    exp[i] <= exp[i-1];
                    done[i] <= 0;
                end else begin
                    done[i] <= valid_pipe[i-1];
                    exp[i] <= exp[i-1];
                    x[i] <= x[i-1];
                    c[i] <= c[i-1];
                    d[i] <= d[i-1];
                end
            end

            data_valid_out <= valid_pipe[11];
            result <= {1'b0, exp[11], c[11][9:0]};
        end
    end

endmodule

`default_nettype wire