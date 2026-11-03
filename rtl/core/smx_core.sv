// smx_core.sv - top of the softmax core: CSR, X_BUF, Y_BUF, controller and datapath.
// Wiring plus the sideband tag pipeline only; no arithmetic here.
// Contract: docs/spec/cross-block.md sections 2, 3, 4.10. Ports: REQ-IF-06 and REQ-IF-10.
module smx_core #(
  parameter int P     = smx_pkg::P,       // lanes: 4, 8 or 16
  parameter int N_SEG = smx_pkg::N_SEG    // PWL segments: 4, 8 or 16
) (
  input  logic        clk,
  input  logic        rst_n,
  // simple memory-mapped access port
  input  logic [12:0] acc_addr,
  input  logic        acc_write,
  input  logic [31:0] acc_writedata,
  input  logic [3:0]  acc_byteenable,
  input  logic        acc_read,
  output logic [31:0] acc_readdata,
  // status conduit
  output logic        status_busy,
  output logic        status_done,
  output logic        status_err
);

  localparam int BANKS  = P / 4;
  localparam int ADDR_W = $clog2(8192 / P);
  localparam int TW     = 3 + P;          // data tag bits: {en, last, first, pass2}

  // ---- tap points of the sideband, in cycles after smx_ctrl issues a group (cross-block.md 3) ----
  localparam int T_SCALE = smx_pkg::BUF_LAT;                    // q at smx_scale
  localparam int T_MAXT  = T_SCALE + smx_pkg::SCALE_LAT;        // c at smx_maxtree
  localparam int T_EXP   = T_MAXT + smx_pkg::MAXTREE_LAT;       // u, m at smx_exp2
  localparam int T_E     = T_EXP + smx_pkg::EXP2_LAT;           // E at sumacc / norm
  localparam int T_SUM   = T_E + smx_pkg::SUMACC_LAT;           // sum_out of the group
  localparam int T_Y     = T_E + smx_pkg::NORM_LAT;           // y at Y_BUF write port
  localparam int D_MAX   = (T_SUM > T_Y) ? T_SUM : T_Y;

  // field positions inside the tag
  localparam int F_P2 = 0, F_FIRST = 1, F_LAST = 2, F_EN = 3;

  // ---- csr <-> buffers ----
  logic [smx_pkg::L_W-1:0] len;
  logic [smx_pkg::R_W-1:0] rows;
  logic [smx_pkg::K_W-1:0] k;
  logic                    start, run_done;
  logic [BANKS-1:0]        x_wr_en;
  logic [3:0]              x_wr_be;
  logic [ADDR_W-1:0]       x_wr_addr;
  logic [BANKS*32-1:0]     x_wr_data;
  logic [ADDR_W-1:0]       buf_rd_addr;
  logic [BANKS*32-1:0]     x_rd_data, y_rd_data;

  // ---- ctrl ----
  logic                    grp_valid, grp_pass2, grp_first, grp_last;
  logic [P-1:0]            grp_en;
  logic [ADDR_W-1:0]       grp_addr, y_wr_addr;
  logic                    sum_last, div_start, div_done, y_valid, y_last;

  // ---- datapath ----
  logic [P-1:0][smx_pkg::Q_W-1:0] q_lane;
  logic [P-1:0][smx_pkg::U_W-1:0] u_lane, u_dly;
  logic [P-1:0][smx_pkg::C_W-1:0] c_lane;
  logic [smx_pkg::C_W-1:0]        m_out;
  logic [smx_pkg::DM_W-1:0]       dm_out, dm_dly;
  logic [P-1:0][smx_pkg::E_W-1:0] e_lane;
  logic [smx_pkg::SUM_W-1:0]      sum_out;
  logic [smx_pkg::RCP_W-1:0]      rcp_out;
  logic [P-1:0][smx_pkg::Y_W-1:0] y_lane;

  logic [ADDR_W-1:0] x_rd_addr;
  assign x_rd_addr = status_busy ? grp_addr : buf_rd_addr;

  smx_csr #(.P(P), .N_SEG(N_SEG)) u_csr (
    .clk, .rst_n,
    .acc_addr, .acc_write, .acc_read, .acc_writedata, .acc_byteenable, .acc_readdata,
    .status_busy, .status_done, .status_err,
    .len, .rows, .k, .start, .run_done,
    .x_wr_en, .x_wr_be, .x_wr_addr, .x_wr_data,
    .buf_rd_addr, .x_rd_data, .y_rd_data
  );

  smx_ctrl #(.P(P)) u_ctrl (
    .clk, .rst_n, .start, .len, .rows,
    .grp_valid, .grp_pass2, .grp_first, .grp_last, .grp_en, .grp_addr,
    .sum_last, .div_start, .div_done, .y_valid, .y_last, .y_wr_addr, .run_done
  );

  smx_buf #(.P(P)) u_xbuf (
    .clk,
    .wr_en(x_wr_en), .wr_be(x_wr_be), .wr_addr(x_wr_addr), .wr_data(x_wr_data),
    .rd_addr(x_rd_addr), .rd_data(x_rd_data)
  );

  smx_buf #(.P(P)) u_ybuf (
    .clk,
    .wr_en({BANKS{y_valid}}), .wr_be(4'hF), .wr_addr(y_wr_addr), .wr_data(y_lane),
    .rd_addr(buf_rd_addr), .rd_data(y_rd_data)
  );

  // ---------------------------------------------------------------------------------------
  // Sideband: vld_q[d-1] / tag_q[d-1] is the tag of the group issued d cycles ago.
  // Only the valid bits are reset; the tag data is meaningful only together with valid.
  // ---------------------------------------------------------------------------------------
  logic            vld_q [D_MAX];
  logic [TW-1:0]   tag_q [D_MAX];
  logic [TW-1:0]   tag_in;

  assign tag_in = {grp_en, grp_last, grp_first, grp_pass2};

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < D_MAX; i++) vld_q[i] <= 1'b0;
    end else begin
      vld_q[0] <= grp_valid;
      for (int i = 1; i < D_MAX; i++) vld_q[i] <= vld_q[i-1];
    end
  end

  always_ff @(posedge clk) begin
    tag_q[0] <= tag_in;
    for (int i = 1; i < D_MAX; i++) tag_q[i] <= tag_q[i-1];
  end

  logic            v_scale, v_maxt, v_exp, v_e, v_sum, v_y;
  logic [TW-1:0]   t_maxt, t_exp, t_e, t_sum, t_y;

  assign v_scale = vld_q[T_SCALE-1];
  assign v_maxt  = vld_q[T_MAXT-1];
  assign t_maxt  = tag_q[T_MAXT-1];
  assign v_exp   = vld_q[T_EXP-1];
  assign t_exp   = tag_q[T_EXP-1];
  assign v_e     = vld_q[T_E-1];
  assign t_e     = tag_q[T_E-1];
  assign v_sum   = vld_q[T_SUM-1];
  assign t_sum   = tag_q[T_SUM-1];
  assign v_y     = vld_q[T_Y-1];
  assign t_y     = tag_q[T_Y-1];

  assign sum_last = v_sum & ~t_sum[F_P2] & t_sum[F_LAST];
  assign y_valid  = v_y & t_y[F_P2];
  assign y_last   = y_valid & t_y[F_LAST];

  // ---------------------------------------------------------------------------------------
  // Datapath
  // ---------------------------------------------------------------------------------------
  genvar j;
  generate
    for (j = 0; j < P; j++) begin : g_lane
      assign q_lane[j] = x_rd_data[j*8 +: 8];

      smx_scale u_scale (
        .clk, .rst_n,
        .in_valid(v_scale), .q_in(q_lane[j]), .k_in(k),
        .out_valid(), .u_out(u_lane[j]), .c_out(c_lane[j])
      );

      smx_exp2 #(.N_SEG(N_SEG)) u_exp2 (
        .clk, .rst_n,
        .in_valid(v_exp), .in_en(t_exp[F_EN + j]), .u_in(u_dly[j]), .m_in(m_out),
        .out_valid(), .e_out(e_lane[j])
      );

      smx_norm u_norm (
        .clk, .rst_n,
        .in_valid(v_e & t_e[F_P2]), .e_in(e_lane[j]), .rcp_in(rcp_out),
        .out_valid(), .y_out(y_lane[j])
      );
    end
  endgenerate

  smx_delay #(.WIDTH(P*smx_pkg::U_W), .DEPTH(smx_pkg::MAXTREE_LAT)) u_u_dly (
    .clk, .in_data(u_lane), .out_data(u_dly)
  );

  smx_maxtree #(.P(P)) u_maxtree (
    .clk, .rst_n,
    .in_valid(v_maxt & ~t_maxt[F_P2]), .in_first(t_maxt[F_FIRST]), .in_en(t_maxt[F_EN +: P]),
    .c_in(c_lane),
    .out_valid(), .m_out, .dm_out
  );

  smx_delay #(.WIDTH(smx_pkg::DM_W), .DEPTH(smx_pkg::EXP2_LAT)) u_dm_dly (
    .clk, .in_data(dm_out), .out_data(dm_dly)
  );

  smx_sumacc #(.P(P)) u_sumacc (
    .clk, .rst_n,
    .in_valid(v_e & ~t_e[F_P2]), .in_first(t_e[F_FIRST]),
    .e_in(e_lane), .dm_in(dm_dly),
    .out_valid(), .sum_out
  );

  smx_divider u_div (
    .clk, .rst_n,
    .start(div_start), .sum_in(sum_out),
    .done(div_done), .rcp_out
  );

endmodule
