`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module pulser #(
    parameter FIELDS = 1,
    parameter CLK_PERIOD_NS = 10,
    parameter DEBOUNCE_TIME_MS = 5
) (
    input wire clk_in,
    input wire rst_in,
    input wire [FIELDS-1:0] inputs,
    output logic [FIELDS-1:0] outputs
);

    logic [FIELDS-1:0] clean;
    logic [FIELDS-1:0] old_clean;
    logic [FIELDS-1:0] pulses;
    assign outputs = pulses;

    // debouncer for every input
    generate
        genvar i;
        for (i=0; i<FIELDS; i=i+1)begin
            debouncer #(
                .CLK_PERIOD_NS(10),
                .DEBOUNCE_TIME_MS(5)
            ) db (
                .clk_in(clk_in),
                .rst_in(rst_in),
                .dirty_in(inputs[i]),
                .clean_out(clean[i])
            );
        end
    endgenerate
    
    // cleaning the input button
    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            // clean <= 0;
            old_clean <= 0;
            pulses <= 0;
        end else begin
            old_clean <= clean;
            for (int i=0; i<FIELDS; i = i+1)begin
                if (pulses[i]) begin
                    pulses[i] <= 0;
                end else if (clean[i] && !old_clean[i]) begin //rising edge
                    pulses[i] <= 1;
                end
            end
        end
    end

endmodule

`default_nettype wire