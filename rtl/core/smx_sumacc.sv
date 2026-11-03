// smx_sumacc.sv - pass-1 accumulator: sum <- first ? S : (sum >> dm) + S, S = sum of P lanes of E.
//
// Bit-exact with group_sum() in model/softmax_ref.py (spec: docs/spec/blocks/smx_sumacc.md).
// Fixed 3-stage pipeline (= smx_pkg::SUMACC_LAT), no stall, one group per cycle:
//   stage 1  partial sums of GS adjacent lanes          (NG partials)
//   stage 2  sum of the NG partials                      (tree total S)
//   stage 3  accumulate: shift old sum by dm (truncating), add S; first ignores old sum
// dm_in and in_first are delayed beside the data to stage 3.
module smx_sumacc #(
  parameter int P = smx_pkg::P                             // 4, 8 or 16
) (
  input  logic                               clk,
  input  logic                               rst_n,
  input  logic                               in_valid,
  input  logic                               in_first,     // first group of the row; only meaningful with in_valid
  input  logic [P-1:0][smx_pkg::E_W-1:0]     e_in,         // UQ1.15, masked lanes already 0
  input  logic        [smx_pkg::DM_W-1:0]    dm_in,        // Mnew - M, same cycle as e_in
  output logic                               out_valid,
  output logic        [smx_pkg::SUM_W-1:0]   sum_out       // holds until the next group
);

  localparam int E_W   = smx_pkg::E_W;
  localparam int DM_W  = smx_pkg::DM_W;
  localparam int SUM_W = smx_pkg::SUM_W;
  localparam int GS    = (P == 4) ? 2 : 4;                 // lanes per stage-1 adder
  localparam int NG    = P / GS;                           // stage-1 partials: 2 (P=4,8) or 4 (P=16)
  localparam int PS_W  = E_W + $clog2(GS);                 // partial sum width
  localparam int TS_W  = E_W + $clog2(P);                  // tree total width (<= 2^19)

  // ---------------------------------------------------------------------------
  // Stage 1: NG partial sums
  // ---------------------------------------------------------------------------
  logic [NG-1:0][PS_W-1:0] part_d;
  genvar gi;
  generate
    for (gi = 0; gi < NG; gi++) begin : g_part
      always_comb begin
        part_d[gi] = '0;
        for (int j = 0; j < GS; j++)
          part_d[gi] = part_d[gi] + PS_W'(e_in[gi*GS + j]);
      end
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Stage 2: tree total
  // ---------------------------------------------------------------------------
  logic [NG-1:0][PS_W-1:0] s1_part_q;
  logic [DM_W-1:0]         s1_dm_q;
  logic                    s1_first_q;
  logic [TS_W-1:0]         tot_d;

  always_comb begin
    tot_d = '0;
    for (int j = 0; j < NG; j++)
      tot_d = tot_d + TS_W'(s1_part_q[j]);
  end

  // ---------------------------------------------------------------------------
  // Stage 3: accumulate
  // ---------------------------------------------------------------------------
  logic [TS_W-1:0]  s2_tot_q;
  logic [DM_W-1:0]  s2_dm_q;
  logic             s2_first_q;
  logic [SUM_W-1:0] sum_q;
  logic [SUM_W-1:0] acc_d;

  // Logical right shift by dm: a shift amount >= SUM_W gives 0 (SystemVerilog semantics).
  assign acc_d = s2_first_q ? SUM_W'(s2_tot_q) : ((sum_q >> s2_dm_q) + SUM_W'(s2_tot_q));

  logic s1_vld_q;
  logic s2_vld_q;
  logic vld_q;

  // Data path: no reset. sum_q only updates when a group reaches stage 3.
  always_ff @(posedge clk) begin
    s1_part_q  <= part_d;
    s1_dm_q    <= dm_in;
    s1_first_q <= in_first;
    s2_tot_q   <= tot_d;
    s2_dm_q    <= s1_dm_q;
    s2_first_q <= s1_first_q;
    if (s2_vld_q) sum_q <= acc_d;
  end

  // Valid chain: three stages, must equal smx_pkg::SUMACC_LAT.
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
  assign sum_out   = sum_q;

endmodule
