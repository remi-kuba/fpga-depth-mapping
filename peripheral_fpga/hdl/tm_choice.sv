
module tm_choice (
  input wire [7:0] data_in,
  output logic [8:0] qm_out
  );


  logic [3:0] cnt;

  always_comb begin 
    cnt = 0;
    for (integer  i = 0; i < 8; i = i + 1) begin
      cnt = cnt + data_in[i];
    end

    qm_out[0] = data_in[0];
    qm_out[8] = ~((cnt > 4) || ((cnt == 4) && ~data_in[0])); // xor route

    for (integer i = 1; i < 8; i = i + 1) begin
      qm_out[i] = qm_out[i-1] ^ data_in[i];
      qm_out[i] = (qm_out[8])? qm_out[i] : ~qm_out[i];
    end
    
  end

endmodule //end tm_choice
