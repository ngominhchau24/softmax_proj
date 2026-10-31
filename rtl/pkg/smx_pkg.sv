// smx_pkg.sv - shared parameters for the smx softmax accelerator.
// Values must match docs/requirements.md (sections 2, 4, 5) and model/softmax_ref.py.
package smx_pkg;

  // ---- synthesis parameters (v1.0) ----
  localparam int P          = 8;     // lanes
  localparam int L_MAX      = 512;   // max row length (power of 2)
  localparam int R_MAX      = 16;    // max rows per run
  localparam int N_SEG      = 8;     // PWL segments for 2^F
  localparam int VERSION    = 8'h10; // HW_PARAM[31:24], v1.0

  // ---- arithmetic widths (requirements section 4) ----
  localparam int Q_W        = 8;     // input int8
  localparam int K_W        = 16;    // SCALE_K, UQ0.16
  localparam int U_FRAC     = 16;    // fractional bits of u = q*K
  localparam int U_W        = Q_W + K_W + 1;  // 25-bit signed u
  localparam int C_W        = 9;     // ceil(u/2^16), signed
  localparam int E_W        = 16;    // E = 2^F, UQ1.15
  localparam int EXP_CUTOFF = 15;    // E = 0 when -I > EXP_CUTOFF
  localparam int SUM_W      = 26;    // >= log2(L_MAX*2^16)+1
  localparam int RECIP_SH   = 40;    // Rcp = floor(2^40 / sum)
  localparam int RCP_W      = 27;
  localparam int OUT_SH     = 32;    // y = (E*Rcp + 2^31) >> 32
  localparam int Y_W        = 8;     // output uint8

  // ---- derived ----
  localparam int LANE_IDX_W = $clog2(P);
  localparam int L_W        = $clog2(L_MAX) + 1;  // LEN register width (1..L_MAX)
  localparam int R_W        = $clog2(R_MAX) + 1;  // ROWS register width (1..R_MAX)
  localparam int SEG_W      = $clog2(N_SEG);

  // ---- CSR byte offsets (requirements 5.2) ----
  localparam logic [15:0] CSR_CTRL      = 16'h0000;
  localparam logic [15:0] CSR_STATUS    = 16'h0004;
  localparam logic [15:0] CSR_LEN       = 16'h0008;
  localparam logic [15:0] CSR_ROWS      = 16'h000C;
  localparam logic [15:0] CSR_SCALE_K   = 16'h0010;
  localparam logic [15:0] CSR_CYCLE_CNT = 16'h0014;
  localparam logic [15:0] CSR_HW_PARAM  = 16'h0018;
  localparam logic [15:0] XBUF_BASE     = 16'h2000;
  localparam logic [15:0] YBUF_BASE     = 16'h4000;
  localparam logic [15:0] SPAN          = 16'h6000;

  // ---- PWL table for N_SEG = 8 (generated: python3 model/softmax_ref.py --gen-pwl 8) ----
  localparam logic [15:0] PWL_C_N8 [8] = '{16'd32768, 16'd35734, 16'd38968, 16'd42495,
                                            16'd46341, 16'd50535, 16'd55109, 16'd60097};
  localparam logic [15:0] PWL_M_N8 [8] = '{16'd2966,  16'd3234,  16'd3527,  16'd3846,
                                            16'd4194,  16'd4574,  16'd4988,  16'd5439};

endpackage
