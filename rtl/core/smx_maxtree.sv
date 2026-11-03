// smx_maxtree.sv - P-lane signed max tree with running max M (IntMax, pass 1 only).
//
// Bit-exact with the group loop of softmax_row() in model/softmax_ref.py
// (spec: docs/spec/blocks/smx_maxtree.md):
//   Mg   = max(c_k over enabled lanes)
//   Mnew = first ? Mg : max(M, Mg)
//   dM   = first ? 0  : Mnew - M          (0..254)
//   M    = Mnew
// Fixed 2-stage pipeline (= smx_pkg::MAXTREE_LAT), no stall, one group per cycle.
//   Stage 1: mask lanes, reduce P lanes to 2 candidates (log2(P)-1 compare levels)
//   Stage 2: last compare level, compare with M, update M, compute dM
// m_out holds its value while in_valid is low (so it also serves pass 2).
module smx_maxtree #(
  parameter int P = smx_pkg::P                             // 4, 8 or 16
) (
  input  logic                                  clk,
  input  logic                                  rst_n,
  input  logic                                  in_valid,  // pass 1 group present
  input  logic                                  in_first,  // first group of the row; only counts with in_valid
  input  logic [P-1:0]                          in_en,     // lane holds a real element; lane 0 always set
  input  logic [P-1:0][smx_pkg::C_W-1:0]        c_in,      // c = ceil(u/2^16), signed; masked lanes may be X
  output logic                                  out_valid,
  output logic [smx_pkg::C_W-1:0]               m_out,     // Mnew, signed; held when no new group
  output logic [smx_pkg::DM_W-1:0]              dm_out     // Mnew - M, unsigned; 0 for the first group
);

  localparam int C_W = smx_pkg::C_W;
  localparam int DM_W = smx_pkg::DM_W;
  localparam int LV   = $clog2(P) - 1;                     // compare levels in stage 1

  // Smaller than every legal c (c is in [-127, 127]); written as a bit pattern, not -9'sd256
  localparam logic signed [C_W-1:0] NEG_INF = 9'b1_0000_0000;

  // ---------------------------------------------------------------------------
  // Stage 1 (combinational): mask, reduce to two candidates
  // ---------------------------------------------------------------------------
  logic signed [C_W-1:0] lvl [LV+1][P];

  always_comb begin
    for (int i = 0; i < P; i++)
      lvl[0][i] = in_en[i] ? $signed(c_in[i]) : NEG_INF;
    for (int l = 0; l < LV; l++)
      for (int j = 0; j < (P >> (l + 1)); j++)
        lvl[l+1][j] = (lvl[l][2*j] > lvl[l][2*j+1]) ? lvl[l][2*j] : lvl[l][2*j+1];
  end

  // ---------------------------------------------------------------------------
  // Pipeline registers
  // ---------------------------------------------------------------------------
  logic signed [C_W-1:0] s1_a_q;
  logic signed [C_W-1:0] s1_b_q;
  logic                  s1_first_q;
  logic                  s1_vld_q;
  logic signed [C_W-1:0] m_q;
  logic        [DM_W-1:0] dm_q;
  logic                  vld_q;

  // Stage 2 (combinational part)
  logic signed [C_W-1:0] mg;
  logic signed [C_W-1:0] mnew;
  logic signed [C_W-1:0] diff;
  logic                  up;                               // Mg raises M

  assign mg   = (s1_a_q > s1_b_q) ? s1_a_q : s1_b_q;
  assign up   = s1_first_q | (mg > m_q);
  assign mnew = up ? mg : m_q;
  assign diff = mg - m_q;                                  // 9 bit, only read when up and not first

  // Data registers carry no reset. M and dM change only with a valid group; before the
  // first group of a run they hold whatever they held, and no output means anything then.
  always_ff @(posedge clk) begin
    s1_a_q     <= lvl[LV][0];
    s1_b_q     <= lvl[LV][1];
    s1_first_q <= in_first;
    if (s1_vld_q) begin
      m_q  <= mnew;
      dm_q <= (s1_first_q | ~up) ? '0 : diff[DM_W-1:0];
    end
  end

  // Valid chain: two stages, must equal smx_pkg::MAXTREE_LAT.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_vld_q <= 1'b0;
      vld_q    <= 1'b0;
    end else begin
      s1_vld_q <= in_valid;
      vld_q    <= s1_vld_q;
    end
  end

  assign out_valid = vld_q;
  assign m_out     = m_q;
  assign dm_out    = dm_q;

endmodule
