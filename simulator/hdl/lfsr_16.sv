module lfsr_16 ( 
    input wire clk_in, 
    input wire rst_in,
    input wire [15:0] seed_in,
    output logic [15:0] q_out);

    logic q [15:0];
    logic [15:0] combined;
    
    always_comb begin 
        for (int i=0; i<16; i = i+1) begin
            combined[i] = q[i];
        end
        q_out = combined;
    end

    always_ff @( posedge clk_in ) begin 
        if (rst_in) begin
            for (int i=0; i<16; i = i+1) begin
                q[i] <= seed_in[i];
            end
        end else begin
            q[0] <= q[15];
            q[1] <= q[0];
            q[2] <= q[1] ^ q[15];
            for (int i=3; i<15; i = i+1) begin
                q[i] <= q[i-1];
            end
            q[15] <= q[14] ^ q[15];

        end
    end
    
endmodule
