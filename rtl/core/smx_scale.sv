// smx_scale.sv - one lane of u = q*K and c = ceil(u / 2^16).
//
// Bit-exact with softmax_ref.py (spec: docs/spec/blocks/smx_scale.md):
//   u = q * K                          signed 8 x unsigned 16 -> signed Q8.16, 25 bit
//   c = ceil_q16(u) = u[24:16] + (u[15:0] != 0)      -((-u) >> 16), 9 bit, in [-127, 127]
// Fixed 3-stage pipeline (= smx_pkg::SCALE_LAT), no stall, one element per cycle.
module smx_scale (
  input  logic                           clk,
  input  logic                           rst_n,
  input  logic                           in_valid,
  input  logic signed [smx_pkg::Q_W-1:0] q_in,             // signed INT8
  input  logic        [smx_pkg::K_W-1:0] k_in,             // UQ0.16
  output logic                           out_valid,
  output logic signed [smx_pkg::U_W-1:0] u_out,            // Q8.16, u = q*K
  output logic signed [smx_pkg::C_W-1:0] c_out             // ceil(u / 2^16)
);

  localparam int Q_W    = smx_pkg::Q_W;
  localparam int K_W    = smx_pkg::K_W;
  localparam int U_W    = smx_pkg::U_W;
  localparam int C_W    = smx_pkg::C_W;
  localparam int U_FRAC = smx_pkg::U_FRAC;

  logic signed [Q_W-1:0] s1_q_q;      // multiplier input registers
  logic signed [K_W:0]   s1_k_q;      // K with a zero sign bit, 17 bit signed
  logic signed [U_W-1:0] s2_prod_q;   // multiplier output register
  logic signed [U_W-1:0] s3_u_q;
  logic signed [C_W-1:0] s3_c_q;
  logic                  s1_vld_q;
  logic                  s2_vld_q;
  logic                  vld_q;

  // 8 x 17 signed multiply. $signed(q) * k_in alone would be unsigned (mixed
  // signedness), so K gets an explicit zero sign bit.
  logic signed [Q_W+K_W:0] prod;
  assign prod = s1_q_q * s1_k_q;       // 25 bit, fits U_W exactly

  // ceil(u / 2^16): add one when any fractional bit is set. u[24:16] >= -128 and
  // the result is <= 127, so no overflow for legal q, K.
  logic signed [C_W-1:0] c_comb;
  logic                  frac_nz;
  assign frac_nz = |s2_prod_q[U_FRAC-1:0];
  assign c_comb  = $signed(s2_prod_q[U_W-1:U_FRAC]) + $signed({{(C_W-1){1'b0}}, frac_nz});

  // Data registers carry no reset, so Quartus can pack them into the DSP block.
  always_ff @(posedge clk) begin
    s1_q_q    <= q_in;
    s1_k_q    <= $signed({1'b0, k_in});
    s2_prod_q <= prod[U_W-1:0];
    s3_u_q    <= s2_prod_q;
    s3_c_q    <= c_comb;
  end

  // Valid chain: three stages, must equal smx_pkg::SCALE_LAT.
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
  assign u_out     = s3_u_q;
  assign c_out     = s3_c_q;

endmodule
