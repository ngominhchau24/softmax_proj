// smx_norm.sv - one lane of y = min(255, (E * Rcp + 2^31) >> 32), uint8 output.
//
// Bit-exact with norm_out() in model/softmax_ref.py (spec: docs/spec/blocks/smx_norm.md):
//   p = E * Rcp                       16 x 27 unsigned, 43 bit
//   t = p[42:32] + p[31]              (p + 2^31) >> 32, 12 bit, no 43-bit adder
//   y = (t > 255) ? 255 : t[7:0]
// Fixed 3-stage pipeline (= smx_pkg::NORM_LAT), no stall, one element per cycle.
// E = 0 gives y = 0 for any Rcp, which is what a masked lane (k >= L) produces.
module smx_norm (
  input  logic                           clk,
  input  logic                           rst_n,
  input  logic                           in_valid,
  input  logic        [smx_pkg::E_W-1:0] e_in,             // E, UQ1.15
  input  logic      [smx_pkg::RCP_W-1:0] rcp_in,           // Rcp, stable during pass 2
  output logic                           out_valid,
  output logic        [smx_pkg::Y_W-1:0] y_out             // uint8, scale 1/256
);

  localparam int E_W   = smx_pkg::E_W;
  localparam int RCP_W = smx_pkg::RCP_W;
  localparam int Y_W   = smx_pkg::Y_W;
  localparam int SH    = smx_pkg::OUT_SH;                  // 32
  localparam int P_W   = E_W + RCP_W;                      // 43
  localparam int T_W   = P_W - SH + 1;                     // 12, rounded quotient

  logic [E_W-1:0]   s1_e_q;
  logic [RCP_W-1:0] s1_r_q;
  logic [P_W-1:0]   s2_prod_q;
  logic [Y_W-1:0]   y_q;
  logic             s1_vld_q;
  logic             s2_vld_q;
  logic             vld_q;

  logic [T_W-1:0]   t;

  // Round half up on the 32 dropped bits: add bit 31 to the upper part.
  assign t = {1'b0, s2_prod_q[P_W-1:SH]} + {{(T_W-1){1'b0}}, s2_prod_q[SH-1]};

  // Data registers carry no reset, so Quartus can pack the multiplier
  // input/output registers into the DSP block.
  always_ff @(posedge clk) begin
    // stage 1: multiplier input registers
    s1_e_q    <= e_in;
    s1_r_q    <= rcp_in;
    // stage 2: 16 x 27 unsigned multiply, full 43-bit product
    s2_prod_q <= s1_e_q * s1_r_q;
    // stage 3: round and saturate to uint8
    y_q       <= (t[T_W-1:Y_W] != '0) ? {Y_W{1'b1}} : t[Y_W-1:0];
  end

  // Valid chain: three stages, must equal smx_pkg::NORM_LAT.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_vld_q <= 1'b0;
      s2_vld_q <= 1'b0;
      vld_q    <= 1'b0;
    end else begin
      s1_vld_q <= in_valid;
      s2_vld_q <= s1_vld_q;
      vld_q    <= s2_vld_q;
    end
  end

  assign out_valid = vld_q;
  assign y_out     = y_q;

endmodule
