// smx_exp2.sv - one lane of E = 2^(d / 2^16) for d = u - M*2^16 <= 0, E in UQ1.15.
//
// Bit-exact with exp2_neg() in model/softmax_ref.py (spec: docs/spec/blocks/smx_exp2.md):
//   F   = d[15:0] = u[15:0]          M*2^16 has zero low bits, so no borrow
//   s   = -I = M - u[24:16]          9 bit, cannot overflow for legal u, M
//   idx = F[15 -: IDX_W], r = F[R_BITS-1:0]
//   E0  = C[idx] + ((M_[idx] * r) >> R_BITS)            max 65535, no carry out
//   E   = (!in_en || s outside [0, 15]) ? 0 : E0 >> s
// Fixed 3-stage pipeline (= smx_pkg::EXP2_LAT), no stall, one element per cycle.
module smx_exp2 #(
  parameter int N_SEG = smx_pkg::N_SEG                     // 4, 8 or 16
) (
  input  logic                           clk,
  input  logic                           rst_n,
  input  logic                           in_valid,
  input  logic                           in_en,            // lane holds a real element (k < L)
  input  logic signed [smx_pkg::U_W-1:0] u_in,             // u = q*K, Q8.16
  input  logic signed [smx_pkg::C_W-1:0] m_in,             // running (pass 1) or final (pass 2) max M
  output logic                           out_valid,
  output logic        [smx_pkg::E_W-1:0] e_out             // E, UQ1.15; 0 for masked / cut-off lanes
);

  localparam int U_W    = smx_pkg::U_W;
  localparam int C_W    = smx_pkg::C_W;
  localparam int E_W    = smx_pkg::E_W;
  localparam int U_FRAC = smx_pkg::U_FRAC;
  localparam int IDX_W  = $clog2(N_SEG);
  localparam int R_BITS = U_FRAC - IDX_W;                  // width of r and of M_[i]
  localparam int SH_W   = $clog2(smx_pkg::EXP_CUTOFF + 1); // shift amount 0..15

  // ---------------------------------------------------------------------------
  // Stage 1 (combinational): split u, PWL lookup, shift amount and kill
  // ---------------------------------------------------------------------------
  logic [IDX_W-1:0]      idx;
  logic [R_BITS-1:0]     r;
  logic signed [C_W-1:0] sh_full;
  logic                  kill;
  logic [E_W-1:0]        c_sel;
  logic [15:0]           m_sel;

  assign idx     = u_in[U_FRAC-1 -: IDX_W];
  assign r       = u_in[R_BITS-1:0];
  assign sh_full = m_in - $signed(u_in[U_W-1:U_FRAC]);
  assign kill    = ~in_en | (sh_full[C_W-1:SH_W] != '0);

  generate
    if (N_SEG == 4) begin : g_n4
      always_comb begin
        c_sel = smx_pkg::PWL_C_N4[idx];
        m_sel = smx_pkg::PWL_M_N4[idx];
      end
    end else if (N_SEG == 8) begin : g_n8
      always_comb begin
        c_sel = smx_pkg::PWL_C_N8[idx];
        m_sel = smx_pkg::PWL_M_N8[idx];
      end
    end else if (N_SEG == 16) begin : g_n16
      always_comb begin
        c_sel = smx_pkg::PWL_C_N16[idx];
        m_sel = smx_pkg::PWL_M_N16[idx];
      end
    end else begin : g_bad
      // Unsupported N_SEG: this module does not exist, so elaboration fails on purpose.
      smx_exp2_unsupported_n_seg u_bad ();
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Pipeline registers
  // ---------------------------------------------------------------------------
  logic [E_W-1:0]        s1_c_q;
  logic [R_BITS-1:0]     s1_m_q;
  logic [R_BITS-1:0]     s1_r_q;
  logic [SH_W-1:0]       s1_sh_q;
  logic                  s1_kill_q;
  logic [2*R_BITS-1:0]   s2_prod_q;
  logic [E_W-1:0]        s2_c_q;
  logic [SH_W-1:0]       s2_sh_q;
  logic                  s2_kill_q;
  logic [E_W-1:0]        e0;
  logic [E_W-1:0]        e_q;
  logic                  s1_vld_q;
  logic                  s2_vld_q;
  logic                  vld_q;

  // E0 = C + floor(prod / 2^R_BITS)
  assign e0 = s2_c_q + s2_prod_q[2*R_BITS-1:R_BITS];

  // Data registers carry no reset, so Quartus can pack the multiplier
  // input/output registers into the DSP block.
  always_ff @(posedge clk) begin
    // stage 1
    s1_c_q    <= c_sel;
    s1_m_q    <= m_sel[R_BITS-1:0];                        // M_[i] fits R_BITS bits (spec 4.3)
    s1_r_q    <= r;
    s1_sh_q   <= sh_full[SH_W-1:0];
    s1_kill_q <= kill;
    // stage 2: R_BITS x R_BITS unsigned multiply
    s2_prod_q <= s1_m_q * s1_r_q;
    s2_c_q    <= s1_c_q;
    s2_sh_q   <= s1_sh_q;
    s2_kill_q <= s1_kill_q;
    // stage 3: add, shift, kill
    e_q       <= s2_kill_q ? '0 : (e0 >> s2_sh_q);
  end

  // Valid chain: three stages, must equal smx_pkg::EXP2_LAT.
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
  assign e_out     = e_q;

endmodule
