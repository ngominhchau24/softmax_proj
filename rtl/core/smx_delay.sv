// smx_delay.sv - delays WIDTH data bits by DEPTH cycles, no reset, DEPTH >= 1.
module smx_delay #(
  parameter int WIDTH = 1,
  parameter int DEPTH = 1
) (
  input  logic             clk,
  input  logic [WIDTH-1:0] in_data,
  output logic [WIDTH-1:0] out_data
);

  logic [WIDTH-1:0] pipe_q [DEPTH];

  always_ff @(posedge clk) begin
    pipe_q[0] <= in_data;
    for (int i = 1; i < DEPTH; i++)
      pipe_q[i] <= pipe_q[i-1];
  end

  assign out_data = pipe_q[DEPTH-1];

endmodule
