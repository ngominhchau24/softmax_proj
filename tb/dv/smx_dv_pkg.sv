// smx_dv_pkg.sv - constants of the DV environment (simulation only).
//
// Every value here is copied from the frozen contract in docs/requirements.md (sections 5.2 and 6),
// on purpose NOT imported from rtl/pkg/smx_pkg.sv: if the RTL package drifts away from the
// requirements, the DV tests must fail instead of following it.
package smx_dv_pkg;

  // ---- limits (requirements section 3) ----
  localparam int L_MAX     = 512;
  localparam int R_MAX     = 16;
  localparam int ROW_WORDS = L_MAX / 4;        // words per row in X_BUF / Y_BUF
  localparam int BUF_BYTES = R_MAX * L_MAX;

  // ---- word addresses on acc_addr = byte offset / 4 (requirements 5.2) ----
  localparam int A_CTRL    = 'h000;
  localparam int A_STATUS  = 'h001;
  localparam int A_LEN     = 'h002;
  localparam int A_ROWS    = 'h003;
  localparam int A_SCALE_K = 'h004;
  localparam int A_CYCLE   = 'h005;
  localparam int A_HWPARAM = 'h006;
  localparam int A_XBUF    = 'h800;            // byte 0x2000
  localparam int A_YBUF    = 'h1000;           // byte 0x4000

  // ---- STATUS bits ----
  localparam logic [31:0] ST_BUSY = 32'h1;
  localparam logic [31:0] ST_DONE = 32'h2;
  localparam logic [31:0] ST_ERR  = 32'h4;

  localparam logic [7:0] HW_VERSION = 8'h10;   // HW_PARAM[31:24], requirements v1.0

  // ---- timing ----
  localparam int ACC_RD_LAT    = 2;            // REQ-IF-02: read data two cycles after the command
  localparam int ROW_LAT_SLACK = 64;           // REQ-PRF-03: row latency <= 2*ceil(L/P) + 64

endpackage
