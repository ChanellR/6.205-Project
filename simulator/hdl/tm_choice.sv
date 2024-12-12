module tm_choice (
  input wire [7:0] data_in,
  output logic [8:0] qm_out
  );

//     Option One:
// The original lsb is assigned to the lsb of the new data frame: 
// The remaining 7 output bits are the XOR of two bits as expressed: 
//  for 
//  where 
//  is the bit number (note 
//  is one way of writing the Exclusive OR operation).
// Option Two:
// The original lsb is assigned to the lsb of the new data frame: 
// The remaining 7 output bits are the XNOR of two bits as expressed 
 
//  for 
//  where 
//  is the bit number. (note the bar overtop implies logical negation of the content contained within. Similar to ~(x && y))


  //count number of 1s 
  logic [3:0] n_1;
  logic [7:0] y_data; 
  integer i; 

  always_comb begin

    n_1 = data_in[0] + data_in[1] + data_in[2] + data_in[3] + data_in[4] + data_in[5] + data_in[6] + data_in[7];  
    if(n_1 > 4 || (n_1 == 4 && data_in[0] == 0)) begin // option 2

        y_data[0] = data_in[0]; 
        for(i = 1; i < 8; i = i+1) begin
            y_data[i] = data_in[i] ~^ y_data[i-1]; 
        end
        qm_out = {1'b0, y_data[7:0]};

    end else begin // option 1

        y_data[0] = data_in[0]; 
        for(i = 1; i < 8; i = i+1) begin
            y_data[i] = data_in[i] ^ y_data[i-1]; 
        end
        qm_out = {1'b1, y_data[7:0]};

    end

  end
 
endmodule