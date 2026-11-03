// smx_csr.sv - register file, acc_* address decode and two-stage read path of smx_core.
//
// Contract: docs/spec/cross-block.md section 4.8, register map: docs/requirements.md 5.2.
// acc_addr is a WORD address (13 bit); smx_pkg::CSR_* are BYTE offsets, so word = byte/4.
//   0..6 CTRL STATUS LEN ROWS SCALE_K CYCLE_CNT HW_PARAM | 7..0x7FF undefined
//   0x800..0xFFF X_BUF | 0x1000..0x17FF Y_BUF | 0x1800..0x1FFF undefined
// Read: command in cycle n, acc_readdata in n+2 (ACC_RD_LAT). Stage 1 (end of n) registers the
// source select, the bank select and the CSR value of cycle n; stage 2 (end of n+1) muxes the
// registered CSR value or the smx_buf data (BUF_LAT = 1) into acc_readdata.
module smx_csr #(
  parameter int P       = smx_pkg::P,                  // 4, 8 or 16
  parameter int N_SEG   = smx_pkg::N_SEG,              // 4, 8 or 16 (only HW_PARAM uses it)
  parameter int BANKS   = P / 4,                       // derived, do not override
  parameter int ADDR_W  = $clog2(8192 / P)             // derived, do not override
) (
  input  logic                    clk,
  input  logic                    rst_n,
  // acc_* port
  input  logic [12:0]             acc_addr,
  input  logic                    acc_write,
  input  logic                    acc_read,
  input  logic [31:0]             acc_writedata,
  input  logic [3:0]              acc_byteenable,
  output logic [31:0]             acc_readdata,
  // status conduit
  output logic                    status_busy,
  output logic                    status_done,
  output logic                    status_err,
  // configuration to smx_ctrl / datapath
  output logic [smx_pkg::L_W-1:0] len,
  output logic [smx_pkg::R_W-1:0] rows,
  output logic [smx_pkg::K_W-1:0] k,
  output logic                    start,
  input  logic                    run_done,
  // X_BUF write port and shared read address
  output logic [BANKS-1:0]        x_wr_en,
  output logic [3:0]              x_wr_be,
  output logic [ADDR_W-1:0]       x_wr_addr,
  output logic [BANKS*32-1:0]     x_wr_data,
  output logic [ADDR_W-1:0]       buf_rd_addr,
  input  logic [BANKS*32-1:0]     x_rd_data,
  input  logic [BANKS*32-1:0]     y_rd_data
);

  localparam int L_W = smx_pkg::L_W;
  localparam int R_W = smx_pkg::R_W;
  localparam int K_W = smx_pkg::K_W;
  localparam int BSH = $clog2(BANKS);

  // HW_PARAM fields come from this block's parameters, not from smx_pkg defaults
  localparam logic [31:0] HW_PARAM_V = {
    8'(smx_pkg::VERSION),            // [31:24]
    4'($clog2(N_SEG)),               // [23:20]
    8'(smx_pkg::R_MAX),              // [19:12]
    4'($clog2(smx_pkg::L_MAX)),      // [11:8]
    8'(P)                            // [7:0]
  };

  generate
    if (P != 4 && P != 8 && P != 16) begin : g_bad_p
      // Unsupported P: this module does not exist, so elaboration fails on purpose.
      smx_csr_unsupported_p u_bad ();
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Address decode over all 13 bits, no aliasing
  // ---------------------------------------------------------------------------
  logic       hit_csr_blk;                 // words 0..7 window
  logic       hit_x, hit_y;
  logic [2:0] reg_idx;
  logic       wr_ctrl, wr_len, wr_rows, wr_k;
  logic       busy_q, done_q, err_q;
  logic       start_cmd, cfg_ok;

  assign hit_csr_blk = (acc_addr[12:3] == 10'd0);
  assign hit_x       = (acc_addr[12:11] == 2'b01);
  assign hit_y       = (acc_addr[12:11] == 2'b10);
  assign reg_idx     = acc_addr[2:0];

  assign wr_ctrl = acc_write & hit_csr_blk & (reg_idx == 3'd0);
  assign wr_len  = acc_write & hit_csr_blk & (reg_idx == 3'd2) & ~busy_q;
  assign wr_rows = acc_write & hit_csr_blk & (reg_idx == 3'd3) & ~busy_q;
  assign wr_k    = acc_write & hit_csr_blk & (reg_idx == 3'd4) & ~busy_q;

  // ---------------------------------------------------------------------------
  // Control registers (reset)
  // ---------------------------------------------------------------------------
  logic [L_W-1:0] len_q;
  logic [R_W-1:0] rows_q;
  logic [K_W-1:0] k_q;
  logic [31:0]    cyc_q;
  logic           start_q;

  assign start_cmd = wr_ctrl & acc_byteenable[0] & acc_writedata[0];
  assign cfg_ok    = (len_q != '0) & (len_q <= L_W'(smx_pkg::L_MAX))
                   & (rows_q != '0) & (rows_q <= R_W'(smx_pkg::R_MAX));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      len_q   <= '0;
      rows_q  <= '0;
      k_q     <= '0;
      busy_q  <= 1'b0;
      done_q  <= 1'b0;
      err_q   <= 1'b0;
      cyc_q   <= '0;
      start_q <= 1'b0;
    end else begin
      start_q <= 1'b0;

      if (wr_len) begin
        if (acc_byteenable[0]) len_q[7:0]      <= acc_writedata[7:0];
        if (acc_byteenable[1]) len_q[L_W-1:8]  <= acc_writedata[L_W-1:8];
      end
      if (wr_rows && acc_byteenable[0]) rows_q <= acc_writedata[R_W-1:0];
      if (wr_k) begin
        if (acc_byteenable[0]) k_q[7:0]  <= acc_writedata[7:0];
        if (acc_byteenable[1]) k_q[15:8] <= acc_writedata[15:8];
      end

      if (busy_q) begin
        cyc_q <= cyc_q + 32'd1;               // counts every BUSY cycle, holds otherwise
        if (run_done) begin
          busy_q <= 1'b0;
          done_q <= 1'b1;
        end
      end else if (start_cmd) begin           // START while BUSY is ignored (incl. run_done cycle)
        cyc_q <= '0;
        if (cfg_ok) begin
          busy_q  <= 1'b1;
          done_q  <= 1'b0;
          err_q   <= 1'b0;
          start_q <= 1'b1;
        end else begin
          done_q <= 1'b1;
          err_q  <= 1'b1;
        end
      end
    end
  end

  assign status_busy = busy_q;
  assign status_done = done_q;
  assign status_err  = err_q;
  assign len         = len_q;
  assign rows        = rows_q;
  assign k           = k_q;
  assign start       = start_q;

  // ---------------------------------------------------------------------------
  // X_BUF write port, buffer read address
  // ---------------------------------------------------------------------------
  logic x_wr_hit;
  assign x_wr_hit    = acc_write & hit_x & ~busy_q;
  assign x_wr_be     = acc_byteenable;
  assign x_wr_data   = {BANKS{acc_writedata}};
  assign x_wr_addr   = acc_addr[ADDR_W+BSH-1 : BSH];
  assign buf_rd_addr = acc_addr[ADDR_W+BSH-1 : BSH];

  // bank = low bits of the word address; one bank (P = 4) needs no select
  logic [BANKS-1:0] rd_bank_oh;            // one-hot bank of the current acc_addr
  genvar b;
  generate
    if (BANKS == 1) begin : g_bank1
      assign x_wr_en    = x_wr_hit;
      assign rd_bank_oh = 1'b1;
    end else begin : g_bankn
      for (b = 0; b < BANKS; b++) begin : g_b
        assign x_wr_en[b]    = x_wr_hit & (acc_addr[BSH-1:0] == BSH'(b));
        assign rd_bank_oh[b] = (acc_addr[BSH-1:0] == BSH'(b));
      end
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Read path: stage 1 at the end of the command cycle, stage 2 one cycle later
  // ---------------------------------------------------------------------------
  logic [31:0] csr_val;                    // register value in the command cycle
  always_comb begin
    csr_val = 32'd0;
    if (hit_csr_blk) begin
      case (reg_idx)
        3'd1:    csr_val = {29'd0, err_q, done_q, busy_q};
        3'd2:    csr_val = {{(32-L_W){1'b0}}, len_q};
        3'd3:    csr_val = {{(32-R_W){1'b0}}, rows_q};
        3'd4:    csr_val = {{(32-K_W){1'b0}}, k_q};
        3'd5:    csr_val = cyc_q;
        3'd6:    csr_val = HW_PARAM_V;
        default: csr_val = 32'd0;           // CTRL (write-only) and word 7
      endcase
    end
  end

  logic              s1_csr_q, s1_x_q, s1_y_q;     // source select, control: reset
  logic [31:0]       s1_val_q;                     // data: no reset
  logic [BANKS-1:0]  s1_bank_q;                    // data: no reset
  logic [31:0]       x_word, y_word;
  logic [31:0]       rd_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_csr_q <= 1'b0;
      s1_x_q   <= 1'b0;
      s1_y_q   <= 1'b0;
      rd_q     <= 32'd0;
    end else begin
      s1_csr_q <= acc_read & hit_csr_blk;
      s1_x_q   <= acc_read & hit_x;
      s1_y_q   <= acc_read & hit_y;
      // undefined regions and idle cycles select nothing and give 0
      rd_q     <= ({32{s1_csr_q}} & s1_val_q)
                | ({32{s1_x_q}}   & x_word)
                | ({32{s1_y_q}}   & y_word);
    end
  end

  always_ff @(posedge clk) begin
    s1_val_q  <= csr_val;
    s1_bank_q <= rd_bank_oh;
  end

  // select one 32-bit bank word with the registered one-hot bank
  always_comb begin
    x_word = 32'd0;
    y_word = 32'd0;
    for (int i = 0; i < BANKS; i++) begin
      x_word = x_word | ({32{s1_bank_q[i]}} & x_rd_data[i*32 +: 32]);
      y_word = y_word | ({32{s1_bank_q[i]}} & y_rd_data[i*32 +: 32]);
    end
  end

  assign acc_readdata = rd_q;

endmodule
