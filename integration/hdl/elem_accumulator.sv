`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module elem_accumulator #(
    // parameter PARTICLE_COUNT = 4,
    parameter COUNTER_SIZE = 16,
    parameter MAX_QUEUE_SIZE = 3
) (
    input wire clk_in,
    input wire rst,
    // receiver signals
    input wire [16-1:0] data_in,
    input wire data_valid_in,
    input wire terms_in_flight, // this can be used to know when to stop
    // updater signals
    output logic [16-1:0] data_out, // [sum]
    output logic data_valid_out // this can also go to the scheduler, to let it know that it is done
);

    /* This modules function:
    * receives floats that are sent kept in a queue and then
    * paired to be added together. It will continue to add terms
    * together until the queue is empty, and it receives and ending signal.
    * It will then right the result to a specific memory location, based on
    * the main particle index.  
    * An addition takes 6 cycles, but it is fully pipelined, so it can be written to constantly.
    */

    // This module can listen to the dispatcher to know when there are no more terms in flight
    // and then it can once completed calculating, signal the scheduler that it is done.

    logic finished;
    assign finished = (queue_size == 1) && !terms_in_flight && !adder_busy && !adder_valid_in && !data_valid_in;

    logic [MAX_QUEUE_SIZE-1:0] [15:0] term_queue;
    logic [$clog2(MAX_QUEUE_SIZE)-1:0] queue_size;
    always_ff @(posedge clk_in) begin 
        if (rst) begin
            queue_size <= 0;
            term_queue <= 0;
            adder_a <= 0;
            adder_b <= 0;
            adder_valid_in <= 0;
            data_valid_out <= 0;
        end else begin
            adder_valid_in <= 0;
            data_valid_out <= 0;
            if (adder_valid_out && data_valid_in) begin
                if (queue_size > 1) begin
                    adder_a <= term_queue[queue_size-1];
                    adder_b <= term_queue[queue_size-2];
                    if (queue_size == 3) begin
                        term_queue <= (term_queue << 16 * 2) | {adder_result, data_in};
                    end else begin // 2
                        term_queue <= {adder_result, data_in};
                    end
                    adder_valid_in <= 1;
                end else begin
                    term_queue <= {term_queue, adder_result, data_in};
                    queue_size <= queue_size + 2;
                end
            end else if (data_valid_in) begin
                if (queue_size > 1) begin
                    adder_a <= term_queue[queue_size-1];
                    adder_b <= term_queue[queue_size-2];
                    adder_valid_in <= 1;
                    if (queue_size == 3) begin
                        term_queue <= (term_queue[0] << 16) | {data_in};
                    end else begin // 2
                        term_queue <=  {data_in};
                    end
                    queue_size <= queue_size - 1;
                end else begin
                    term_queue <= {term_queue, data_in};
                    queue_size <= queue_size + 1;
                end
            end else if (adder_valid_out) begin
                if (queue_size > 1) begin
                    adder_a <= term_queue[queue_size-1];
                    adder_b <= term_queue[queue_size-2];
                    adder_valid_in <= 1;
                    if (queue_size == 3) begin
                        term_queue <= (term_queue[0] << 16) | {adder_result};
                    end else begin // 2
                        term_queue <= {adder_result};
                    end
                    queue_size <= queue_size - 1;
                end else begin
                    term_queue <= {term_queue, adder_result};
                    queue_size <= queue_size + 1;
                end
            end else begin
                if (queue_size > 1) begin
                    adder_a <= term_queue[queue_size-1];
                    adder_b <= term_queue[queue_size-2];
                    adder_valid_in <= 1;
                    if (queue_size == 3) begin
                        term_queue <= term_queue[0];
                    end else begin // 2
                        term_queue <= 0;
                    end
                    queue_size <= queue_size - 2;
                end else if (finished) begin
                    // if there is only one term left, and none coming in, and we have a stop signal
                    data_out <= term_queue[0];
                    data_valid_out <= 1; // !is_density_task;
                    // target_index <= main_index;
                    term_queue <= 0;
                    queue_size <= 0;
                end
            end
        end
    end

    logic [15:0] adder_a, adder_b, adder_result;
    logic adder_valid_in, adder_valid_out, adder_busy;
    binary16_adder madder (
        .clk_in(clk_in),
        .rst(rst),
        .a(adder_a),
        .b(adder_b),
        .data_valid_in(adder_valid_in),
        .result(adder_result),
        .data_valid_out(adder_valid_out),
        .busy(adder_busy)
    );

endmodule

`default_nettype wire
