// smx_pkg.sv - shared parameters for the smx softmax accelerator.
// Values must match docs/requirements.md (sections 2, 4, 5) and model/softmax_ref.py.
package smx_pkg;

  // ---- synthesis parameters (v1.0) ----
  localparam int P          = 8;     // lanes, default only: blocks take their own parameter
  localparam int L_MAX      = 512;   // max row length (power of 2)
  localparam int R_MAX      = 16;    // max rows per run
  localparam int N_SEG      = 8;     // PWL segments, default only: blocks take their own parameter
  localparam int VERSION    = 8'h10; // HW_PARAM[31:24], v1.0

  // ---- arithmetic widths (requirements section 4) ----
  localparam int Q_W        = 8;     // input int8
  localparam int K_W        = 16;    // SCALE_K, UQ0.16
  localparam int U_FRAC     = 16;    // fractional bits of u = q*K
  localparam int U_W        = Q_W + K_W + 1;  // 25-bit signed u
  localparam int C_W        = 9;     // ceil(u/2^16), signed
  localparam int DM_W       = 8;     // Mnew - M, 0..254
  localparam int E_W        = 16;    // E = 2^F, UQ1.15
  localparam int EXP_CUTOFF = 15;    // E = 0 when -I > EXP_CUTOFF
  localparam int SUM_W      = 25;    // sum <= L_MAX*2^15 = 2^24, reached at K = 0
  localparam int RECIP_SH   = 40;    // Rcp = floor(2^40 / sum)
  localparam int RCP_W      = 27;
  localparam int OUT_SH     = 32;    // y = (E*Rcp + 2^31) >> 32
  localparam int Y_W        = 8;     // output uint8

  // ---- block latencies in cycles, docs/spec/cross-block.md section 3 ----
  localparam int ACC_RD_LAT  = 2;    // acc_read to acc_readdata (REQ-IF-06)
  localparam int BUF_LAT     = 1;    // smx_buf read address to read data
  localparam int SCALE_LAT   = 3;    // smx_scale in_valid to out_valid
  localparam int MAXTREE_LAT = 2;    // smx_maxtree in_valid to out_valid
  localparam int EXP2_LAT    = 3;    // smx_exp2 in_valid to out_valid
  localparam int SUMACC_LAT  = 3;    // smx_sumacc in_valid to out_valid
  localparam int NORM_LAT    = 3;    // smx_norm in_valid to out_valid
  localparam int DIV_LAT     = 28;   // smx_divider start to done
  localparam int PIPE_LAT    = BUF_LAT + SCALE_LAT + MAXTREE_LAT + EXP2_LAT;  // read address to E
  // T_row = 2*G + ROW_OVERHEAD, CYCLE_CNT = R*T_row + 1 (cross-block.md section 5)
  localparam int ROW_OVERHEAD = 2*PIPE_LAT + SUMACC_LAT + NORM_LAT + DIV_LAT + 2;

  // ---- derived ----
  localparam int L_W        = $clog2(L_MAX) + 1;  // LEN register width (1..L_MAX)
  localparam int R_W        = $clog2(R_MAX) + 1;  // ROWS register width (1..R_MAX)

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

  // ---- PWL table for N_SEG = 4 (generated: python3 model/softmax_ref.py --gen-pwl 4) ----
  localparam logic [15:0] PWL_C_N4 [4] = '{16'd32768, 16'd38968, 16'd46341, 16'd55109};
  localparam logic [15:0] PWL_M_N4 [4] = '{16'd6200, 16'd7373, 16'd8768, 16'd10427};

  // ---- PWL table for N_SEG = 16 (generated: python3 model/softmax_ref.py --gen-pwl 16) ----
  localparam logic [15:0] PWL_C_N16 [16] = '{16'd32768, 16'd34219, 16'd35734, 16'd37316, 16'd38968, 16'd40693, 16'd42495, 16'd44376, 16'd46341, 16'd48393, 16'd50535, 16'd52773, 16'd55109, 16'd57549, 16'd60097, 16'd62757};
  localparam logic [15:0] PWL_M_N16 [16] = '{16'd1451, 16'd1515, 16'd1582, 16'd1652, 16'd1725, 16'd1802, 16'd1881, 16'd1965, 16'd2052, 16'd2143, 16'd2237, 16'd2336, 16'd2440, 16'd2548, 16'd2661, 16'd2779};

  // ---- PWL table for N_SEG = 8 (generated: python3 model/softmax_ref.py --gen-pwl 8) ----
  localparam logic [15:0] PWL_C_N8 [8] = '{16'd32768, 16'd35734, 16'd38968, 16'd42495,
                                            16'd46341, 16'd50535, 16'd55109, 16'd60097};
  localparam logic [15:0] PWL_M_N8 [8] = '{16'd2966,  16'd3234,  16'd3527,  16'd3846,
                                            16'd4194,  16'd4574,  16'd4988,  16'd5439};

endpackage
