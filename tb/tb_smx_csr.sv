// tb_smx_csr.sv - self-checking unit testbench for smx_csr (simulation only).
//
// No arithmetic, so no vector files: expected values come from a cycle model written in this
// file from the contract (docs/spec/cross-block.md 4.8), plus directed checks with literal
// expected values so the model cannot share a bug with the RTL.
// Cycle convention: inputs are driven at a falling edge, one tick = one clock cycle. After a tick
// the DUT shows the state of cycle n+1. X_BUF/Y_BUF are modelled as smx_buf does: rd_data is
// registered from buf_rd_addr, one cycle of delay, banks laid out as BANKS x 32 bit.
// Prints one "TB_RESULT: PASS" or "TB_RESULT: FAIL" line.
`timescale 1ns/1ps

module tb_smx_csr;

  parameter int P     = smx_pkg::P;
  parameter int N_SEG = smx_pkg::N_SEG;

  localparam int BANKS   = P / 4;
  localparam int ADDR_W  = $clog2(8192 / P);
  localparam int MAX_MSG = 20;

  logic                 clk = 1'b0;
  logic                 rst_n;
  logic [12:0]          acc_addr;
  logic                 acc_write, acc_read;
  logic [31:0]          acc_writedata;
  logic [3:0]           acc_byteenable;
  logic [31:0]          acc_readdata;
  logic                 status_busy, status_done, status_err;
  logic [9:0]           len;
  logic [4:0]           rows;
  logic [15:0]          k;
  logic                 start;
  logic                 run_done;
  logic [BANKS-1:0]     x_wr_en;
  logic [3:0]           x_wr_be;
  logic [ADDR_W-1:0]    x_wr_addr;
  logic [BANKS*32-1:0]  x_wr_data;
  logic [ADDR_W-1:0]    buf_rd_addr;
  logic [BANKS*32-1:0]  x_rd_data, y_rd_data;

  always #5 clk = ~clk;

  smx_csr #(.P(P), .N_SEG(N_SEG)) dut (.*);

  // ---- smx_buf read model: registered output, one cycle of delay ----
  function automatic logic [31:0] xf(input int bank, input int a);
    return (32'h9E3779B1 * 32'(a * 8 + bank + 1)) ^ 32'h5A5A1234;
  endfunction
  function automatic logic [31:0] yf(input int bank, input int a);
    return (32'h85EBCA6B * 32'(a * 8 + bank + 3)) ^ 32'hC3C3F00D;
  endfunction

  always_ff @(posedge clk) begin
    for (int b = 0; b < BANKS; b++) begin
      x_rd_data[b*32 +: 32] <= xf(b, int'(buf_rd_addr));
      y_rd_data[b*32 +: 32] <= yf(b, int'(buf_rd_addr));
    end
  end

  // ---- reference model state (value in the command cycle) ----
  logic [9:0]  m_len;
  logic [4:0]  m_rows;
  logic [15:0] m_k;
  logic        m_busy, m_done, m_err, m_start;
  logic [31:0] m_cyc;

  // ---- read scoreboard: expectation of the command issued in the previous tick ----
  logic        pend_v;
  logic [31:0] pend_exp;
  logic [12:0] pend_addr;
  int          tick_no;

  int n_err;
  int n_chk;
  // coverage counters, all must be non-zero for a PASS
  int c_start_ok, c_start_bad, c_start_busy, c_start_rd, c_start_rdone, c_start_after;
  int c_rd_csr, c_rd_x, c_rd_y, c_rd_undef, c_b2b, c_wr_busy_ign, c_xwr, c_cyc_hold;
  int c_rst_mid;

  task automatic fail(input string what);
    n_err++;
    if (n_err <= MAX_MSG)
      $display("ERROR t=%0t tick=%0d: %s", $time, tick_no, what);
  endtask

  task automatic check(input bit cond, input string what);
    n_chk++;
    if (!cond) fail(what);
  endtask

  function automatic logic [31:0] csr_word(input int idx);
    case (idx)
      1:       return {29'd0, m_err, m_done, m_busy};
      2:       return {22'd0, m_len};
      3:       return {27'd0, m_rows};
      4:       return {16'd0, m_k};
      5:       return m_cyc;
      6:       return {8'h10, 4'($clog2(N_SEG)), 8'd16, 4'd9, 8'(P)};  // literals, not smx_pkg
      default: return 32'd0;
    endcase
  endfunction

  function automatic logic [31:0] read_exp(input logic [12:0] a);
    int w;
    w = int'(a[10:0]);
    if (a < 13'd8)                          return csr_word(int'(a));
    else if (a >= 13'h0800 && a <= 13'h0FFF) return xf(w % BANKS, w / BANKS);
    else if (a >= 13'h1000 && a <= 13'h17FF) return yf(w % BANKS, w / BANKS);
    else                                    return 32'd0;
  endfunction

  // One clock cycle. Drives a command, checks the combinational outputs, advances the
  // model, waits one cycle and checks the registered outputs and the read scoreboard.
  task automatic tick(input logic [12:0] a, input bit wr, input bit rd, input logic [31:0] wd,
                      input logic [3:0] be, input bit rdone);
    logic [9:0]  nl;
    logic [4:0]  nr;
    logic [15:0] nk;
    logic        nb, nd, ne, ns, st;
    logic [31:0] ncyc;
    logic [31:0] e_rd;
    logic [BANKS-1:0] e_en;
    int          w;
    bit          is_x;

    tick_no++;
    acc_addr = a; acc_write = wr; acc_read = rd; acc_writedata = wd;
    acc_byteenable = be; run_done = rdone;
    #1;

    // combinational outputs for this command
    w    = int'(a[10:0]);
    is_x = (a >= 13'h0800 && a <= 13'h0FFF);
    e_en = '0;
    if (wr && is_x && !m_busy) e_en = BANKS'(1) << (w % BANKS);
    check(x_wr_en === e_en, $sformatf("x_wr_en=%b exp=%b addr=%h busy=%0b", x_wr_en, e_en, a, m_busy));
    if (e_en != '0) begin
      c_xwr++;
      check(x_wr_addr === ADDR_W'(w / BANKS), $sformatf("x_wr_addr=%h exp=%h", x_wr_addr, w / BANKS));
      check(x_wr_be === be, "x_wr_be");
      for (int b = 0; b < BANKS; b++)
        check(x_wr_data[b*32 +: 32] === wd, "x_wr_data not repeated on every bank");
    end
    if (wr && is_x && m_busy) c_wr_busy_ign++;
    if ((a >= 13'h0800 && a <= 13'h17FF))
      check(buf_rd_addr === ADDR_W'(w / BANKS), $sformatf("buf_rd_addr=%h exp=%h", buf_rd_addr, w / BANKS));

    // model update from the pre-state
    st = wr && (a == 13'd0) && be[0] && wd[0];
    nl = m_len; nr = m_rows; nk = m_k; nb = m_busy; nd = m_done; ne = m_err; ns = 1'b0;
    ncyc = m_cyc;
    if (wr && !m_busy) begin
      if (a == 13'd2) begin
        if (be[0]) nl[7:0] = wd[7:0];
        if (be[1]) nl[9:8] = wd[9:8];
      end
      if (a == 13'd3 && be[0]) nr = wd[4:0];
      if (a == 13'd4) begin
        if (be[0]) nk[7:0]  = wd[7:0];
        if (be[1]) nk[15:8] = wd[15:8];
      end
    end
    if (wr && m_busy && (a == 13'd2 || a == 13'd3 || a == 13'd4)) c_wr_busy_ign++;
    if (m_busy) begin
      ncyc = m_cyc + 32'd1;
      if (rdone) begin nb = 1'b0; nd = 1'b1; end
      if (st) begin
        c_start_busy++;
        if (rdone) c_start_rdone++;
      end
    end else if (st) begin
      ncyc = 32'd0;
      if (m_len >= 10'd1 && m_len <= 10'd512 && m_rows >= 5'd1 && m_rows <= 5'd16) begin
        nb = 1'b1; nd = 1'b0; ne = 1'b0; ns = 1'b1;
        c_start_ok++;
      end else begin
        nd = 1'b1; ne = 1'b1;
        c_start_bad++;
      end
    end
    if (!m_busy && !st && m_cyc != 0) c_cyc_hold++;

    // read expectation, value in the command cycle
    e_rd = read_exp(a);
    if (rd) begin
      if (a < 13'd8) c_rd_csr++;
      else if (is_x) c_rd_x++;
      else if (a >= 13'h1000 && a <= 13'h17FF) c_rd_y++;
      else c_rd_undef++;
      if (pend_v) c_b2b++;
      if (a == 13'd1 && st) c_start_rd++;
    end

    @(negedge clk);

    // state after the edge
    m_len = nl; m_rows = nr; m_k = nk; m_busy = nb; m_done = nd; m_err = ne;
    m_start = ns; m_cyc = ncyc;
    check(status_busy === m_busy, $sformatf("status_busy=%b exp=%b", status_busy, m_busy));
    check(status_done === m_done, $sformatf("status_done=%b exp=%b", status_done, m_done));
    check(status_err  === m_err,  $sformatf("status_err=%b exp=%b", status_err, m_err));
    check(len  === m_len,  $sformatf("len=%h exp=%h", len, m_len));
    check(rows === m_rows, $sformatf("rows=%h exp=%h", rows, m_rows));
    check(k    === m_k,    $sformatf("k=%h exp=%h", k, m_k));
    check(start === m_start, $sformatf("start=%b exp=%b", start, m_start));
    check(!(status_busy && status_done), "BUSY and DONE both 1");

    // read issued in the previous tick is visible now: ACC_RD_LAT = 2 cycles
    if (pend_v)
      check(acc_readdata === pend_exp,
            $sformatf("readdata=%h exp=%h for read addr=%h", acc_readdata, pend_exp, pend_addr));
    pend_v = rd; pend_exp = e_rd; pend_addr = a;
  endtask

  // ---- command helpers ----
  task automatic idle();
    tick(13'h0, 1'b0, 1'b0, $urandom, $urandom, 1'b0);
  endtask
  task automatic wr(input logic [12:0] a, input logic [31:0] d, input logic [3:0] be = 4'hF);
    tick(a, 1'b1, 1'b0, d, be, 1'b0);
  endtask
  task automatic rd(input logic [12:0] a);
    tick(a, 1'b0, 1'b1, $urandom, $urandom, 1'b0);
  endtask
  // read and check the value against a literal after exactly two cycles
  task automatic rd_chk(input logic [12:0] a, input logic [31:0] e, input string what);
    rd(a);
    idle();
    check(acc_readdata === e, $sformatf("%s: readdata=%h exp=%h", what, acc_readdata, e));
  endtask
  task automatic do_start(input bit rdone = 1'b0);
    tick(13'd0, 1'b1, 1'b0, 32'h1, 4'hF, rdone);
  endtask
  task automatic finish_run();      // run_done, then one idle
    tick(13'd0, 1'b0, 1'b0, 32'h0, 4'h0, 1'b1);
  endtask
  task automatic cfg(input int l, input int r, input int kk = 1000);
    wr(13'd2, 32'(l));
    wr(13'd3, 32'(r));
    wr(13'd4, 32'(kk));
  endtask

  task automatic reset_model();
    m_len = '0; m_rows = '0; m_k = '0; m_busy = 0; m_done = 0; m_err = 0; m_start = 0;
    m_cyc = '0; pend_v = 0;
  endtask

  task automatic do_reset(input int cycles = 2);
    rst_n = 1'b0;
    #1;
    reset_model();
    check(acc_readdata === 32'd0, "readdata not cleared by async reset");
    check(status_busy === 1'b0 && status_done === 1'b0 && status_err === 1'b0 && start === 1'b0,
          "status not cleared by async reset");
    repeat (cycles) @(negedge clk);
    rst_n = 1'b1;
  endtask

  // ---- directed tests ----
  task automatic t_reset_values();
    do_reset(3);
    check(len === 10'd0 && rows === 5'd0 && k === 16'd0 && start === 1'b0, "reset values");
    for (int i = 0; i < 6; i++) rd_chk(13'(i), 32'd0, $sformatf("reg %0d after reset", i));
    rd_chk(13'd6, {8'h10, 4'($clog2(N_SEG)), 8'd16, 4'd9, 8'(P)}, "HW_PARAM");
    // START right after reset: LEN = 0 -> ERR
    do_reset(2);
    do_start();
    check(status_busy === 0 && status_done === 1 && status_err === 1 && start === 0,
          "START after reset must give DONE+ERR");
  endtask

  task automatic t_hw_param();
    logic [31:0] e;
    e = {8'h10, 4'($clog2(N_SEG)), 8'h10, 4'h9, 8'(P)};  // VERSION, log2N, R_MAX, log2L_MAX, P
    rd_chk(13'd6, e, "HW_PARAM packing");
    check(e[7:0] == 8'(P) && e[11:8] == 4'd9 && e[19:12] == 8'd16 && e[31:24] == 8'h10, "HW_PARAM literal");
    check(e[23:20] == ((N_SEG == 4) ? 4'd2 : (N_SEG == 8) ? 4'd3 : 4'd4), "HW_PARAM log2 N_SEG");
    wr(13'd6, 32'hFFFFFFFF);
    rd_chk(13'd6, e, "HW_PARAM write ignored");
  endtask

  task automatic t_valid_start();
    do_reset(2);
    cfg(37, 3, 16'hBEEF);
    do_start();                                             // cycle n
    check(status_busy === 1 && status_done === 0 && status_err === 0, "valid START: BUSY at n+1");
    check(start === 1'b1, "start pulse at n+1");
    rd_chk(13'd1, 32'h1, "STATUS read at n+1 sees BUSY");   // read cmd at n+1
    check(start === 1'b0, "start must be one cycle");
    rd_chk(13'd5, 32'd2, "CYCLE_CNT two cycles after the first BUSY cycle");
    idle(); idle(); idle();
    rd_chk(13'd5, 32'd7, "CYCLE_CNT counting");             // 7 busy cycles passed at command cycle
    finish_run();
    check(status_busy === 0 && status_done === 1 && status_err === 0, "run_done: DONE, not BUSY");
    idle(); idle();
    rd_chk(13'd1, 32'h2, "STATUS after run");
    c_cyc_hold += 0;
    begin
      logic [31:0] hold;
      hold = m_cyc;
      repeat (5) idle();
      check(m_cyc == hold, "model sanity");
      rd_chk(13'd5, hold, "CYCLE_CNT holds after run_done");
    end
    // DONE sticky until the next START; second valid START zeroes CYCLE_CNT and clears DONE
    repeat (3) idle();
    rd_chk(13'd1, 32'h2, "DONE sticky");
    do_start();
    check(status_busy === 1 && status_done === 0 && start === 1, "second START clears DONE");
    rd_chk(13'd5, 32'd0, "CYCLE_CNT zeroed by second START");
    finish_run();
  endtask

  task automatic t_invalid_start();
    int ls[$] = '{0, 513, 1023, 1, 512, 1, 512, 100, 100, 100, 100, 100, 100};
    int rs[$] = '{1, 1,   1,    0, 17,  1, 16,  0,   17,  31,  1,   16,  5};
    // L=100 with R=0/17/31 invalid; the other combinations legal (one pair per row)
    do_reset(2);
    wr(13'd4, 32'h1234);
    for (int i = 0; i < ls.size(); i++) begin
      bit legal;
      legal = (ls[i] >= 1 && ls[i] <= 512 && rs[i] >= 1 && rs[i] <= 16);
      cfg(ls[i], rs[i], 16'h1234);
      do_start();
      if (legal) begin
        check(status_busy === 1 && status_done === 0 && status_err === 0 && start === 1,
              $sformatf("legal L=%0d R=%0d must start", ls[i], rs[i]));
        finish_run();
        check(status_err === 0 && status_done === 1, "legal run end");
      end else begin
        check(status_busy === 0 && status_done === 1 && status_err === 1 && start === 0,
              $sformatf("illegal L=%0d R=%0d must give DONE+ERR, no BUSY", ls[i], rs[i]));
        idle();
        check(start === 0, "no start for illegal config");
        rd_chk(13'd5, 32'd0, "CYCLE_CNT 0 after illegal START");
      end
    end
    // ERR cleared by a following legal START
    cfg(0, 1); do_start();
    check(status_err === 1, "ERR set");
    idle(); idle(); check(status_err === 1 && status_done === 1, "ERR sticky");
    cfg(1, 1); do_start();
    check(status_err === 0 && status_done === 0 && status_busy === 1, "legal START clears ERR/DONE");
    finish_run();
    // illegal START clears a held CYCLE_CNT
    cfg(1, 1); do_start(); repeat (4) idle(); finish_run();
    cfg(513, 1); do_start();
    rd_chk(13'd5, 32'd0, "CYCLE_CNT zeroed by illegal START");
  endtask

  task automatic t_start_busy();
    do_reset(2);
    cfg(20, 2);
    do_start();
    repeat (3) idle();
    do_start();                                  // ignored while BUSY
    check(status_busy === 1 && start === 0, "START while BUSY ignored");
    rd_chk(13'd5, 32'd4, "CYCLE_CNT not restarted by START while BUSY");
    // START in the same cycle as run_done: ignored, the run ends
    do_start(1'b1);
    check(status_busy === 0 && status_done === 1 && status_err === 0 && start === 0,
          "START in run_done cycle ignored");
    idle(); check(status_busy === 0 && start === 0, "no deferred start");
    // START in the cycle right after run_done works
    do_start();
    do_start(1'b1);                              // second run: ends together with a START
    do_start();                                  // right after run_done
    check(status_busy === 1 && start === 1 && status_done === 0, "START right after run_done works");
    c_start_after++;
    finish_run();
    // START with byteenable[0] = 0 or writedata[0] = 0 does nothing
    wr(13'd0, 32'h1, 4'hE);
    check(status_busy === 0 && start === 0, "START with be[0]=0");
    wr(13'd0, 32'hFFFFFFFE, 4'hF);
    check(status_busy === 0 && start === 0, "START with wd[0]=0");
    wr(13'd0, 32'hFFFFFFFF, 4'h1);
    check(status_busy === 1 && start === 1, "START with be=1, other bits set");
    finish_run();
    rd_chk(13'd0, 32'd0, "CTRL reads 0");
  endtask

  task automatic t_regs();
    do_reset(2);
    // byte enables, width masking
    wr(13'd2, 32'hFFFF_FFFF, 4'h1); rd_chk(13'd2, 32'h0FF, "LEN be=1");
    wr(13'd2, 32'h0000_0300, 4'h2); rd_chk(13'd2, 32'h3FF, "LEN be=2 -> bits [9:8]");
    wr(13'd2, 32'hFFFF_FFFF, 4'hC); rd_chk(13'd2, 32'h3FF, "LEN be=C ignored");
    wr(13'd2, 32'h0, 4'h3);         rd_chk(13'd2, 32'h000, "LEN cleared");
    wr(13'd2, 32'hFFFF_FF55, 4'hF); rd_chk(13'd2, 32'h355, "LEN upper bits read 0");
    wr(13'd3, 32'hFFFF_FFFF, 4'h1); rd_chk(13'd3, 32'h01F, "ROWS be=1");
    wr(13'd3, 32'h0, 4'h2);         rd_chk(13'd3, 32'h01F, "ROWS be=2 ignored");
    wr(13'd3, 32'h0000_0002, 4'h1); rd_chk(13'd3, 32'h002, "ROWS value");
    wr(13'd4, 32'hFFFF_FFFF, 4'h1); rd_chk(13'd4, 32'h00FF, "K be=1");
    wr(13'd4, 32'hAB00_CD00, 4'h2); rd_chk(13'd4, 32'hCDFF, "K be=2");
    wr(13'd4, 32'h1111_2222, 4'hC); rd_chk(13'd4, 32'hCDFF, "K be=C ignored");
    wr(13'd4, 32'h1111_2222, 4'hF); rd_chk(13'd4, 32'h2222, "K full word");
    // read-only and undefined writes ignored
    wr(13'd1, 32'hFFFFFFFF); rd_chk(13'd1, 32'h0, "STATUS write ignored");
    wr(13'd5, 32'hFFFFFFFF); rd_chk(13'd5, 32'h0, "CYCLE_CNT write ignored");
    wr(13'd7, 32'hFFFFFFFF); rd_chk(13'd7, 32'h0, "word 7 undefined");
    wr(13'h7FF, 32'hFFFFFFFF); rd_chk(13'h7FF, 32'h0, "0x7FF undefined");
    wr(13'h1800, 32'hFFFFFFFF); rd_chk(13'h1800, 32'h0, "0x1800 undefined");
    wr(13'h1FFF, 32'hFFFFFFFF); rd_chk(13'h1FFF, 32'h0, "0x1FFF undefined");
    wr(13'h8, 32'h1);              rd_chk(13'h8, 32'h0, "word 8 not aliased to LEN");
    wr(13'h82, 32'h1);             rd_chk(13'h82, 32'h0, "0x82 not aliased to LEN");
    wr(13'h1002, 32'h1);           rd_chk(13'h2, 32'h355, "Y_BUF write does not touch LEN");
    // address aliasing: decode of upper bits
    rd_chk(13'h1002, yf(2 % BANKS, 2 / BANKS), "Y_BUF word 2 differs from LEN");
    rd_chk(13'h0802, xf(2 % BANKS, 2 / BANKS), "X_BUF word 2 differs from LEN");
    rd_chk(13'h1802, 32'h0, "0x1802 undefined");
    rd_chk(13'h0006, {8'h10, 4'($clog2(N_SEG)), 8'd16, 4'd9, 8'(P)}, "HW_PARAM at word 6");
    rd_chk(13'h0806, xf(6 % BANKS, 6 / BANKS), "X word 6, not HW_PARAM");
    // writes ignored while BUSY
    cfg(30, 2, 16'h4321);
    do_start();
    cfg(99, 9, 16'h9999);
    wr(13'h0900, 32'h12345678);
    wr(13'h0801, 32'h87654321);
    check(x_wr_en === '0, "no X_BUF write while BUSY");
    rd_chk(13'd2, 32'd30, "LEN write ignored while BUSY");
    rd_chk(13'd3, 32'd2, "ROWS write ignored while BUSY");
    rd_chk(13'd4, 32'h4321, "K write ignored while BUSY");
    finish_run();
    cfg(99, 9, 16'h9999);
    rd_chk(13'd2, 32'd99, "LEN writable after run");
  endtask

  // read path: all source orders back to back, with the bank selection around its boundaries
  task automatic t_read_path();
    logic [12:0] addrs[$];
    do_reset(2);
    cfg(77, 5, 16'h5555);
    for (int i = 0; i < 12; i++) begin
      addrs.push_back(13'(13'h0800 + i));
      addrs.push_back(13'(13'h1000 + i));
    end
    addrs.push_back(13'h0FFF); addrs.push_back(13'h17FF); addrs.push_back(13'h0800);
    addrs.push_back(13'h1000); addrs.push_back(13'h7FF); addrs.push_back(13'h1800);
    addrs.push_back(13'h1FFF); addrs.push_back(13'd1); addrs.push_back(13'd2);
    addrs.push_back(13'd3); addrs.push_back(13'd4); addrs.push_back(13'd5);
    addrs.push_back(13'd6); addrs.push_back(13'd7); addrs.push_back(13'd0);
    // all ordered pairs of consecutive reads, then random order streams
    for (int i = 0; i < addrs.size(); i++)
      for (int j = 0; j < addrs.size(); j++) begin
        rd(addrs[i]); rd(addrs[j]);
      end
    for (int i = 0; i < 3000; i++) rd(addrs[$urandom_range(addrs.size() - 1)]);
    // gaps between reads
    for (int i = 0; i < 400; i++) begin
      rd(addrs[$urandom_range(addrs.size() - 1)]);
      if ($urandom_range(1)) idle();
    end
    idle(); idle();
    // STATUS read in the same cycle as a change: must show the pre-change value
    cfg(5, 1);
    tick(13'd1, 1'b1, 1'b1, 32'h1, 4'hF, 1'b0);  // write+read in the same cycle: START cmd is addr 0
    do_start();
    rd(13'd1);                                    // sees BUSY
    tick(13'd1, 1'b0, 1'b1, 32'h0, 4'hF, 1'b1);   // STATUS read in the run_done cycle: still BUSY
    rd(13'd1);                                    // sees DONE
    idle(); idle();
    // read of STATUS in the START command cycle is not possible (same port), check n-1/n+1 only
    rd_chk(13'd1, 32'h2, "STATUS after run");
  endtask

  // ---- random phase ----
  function automatic logic [12:0] rnd_addr();
    int r;
    r = $urandom_range(99);
    if (r < 30)      return 13'($urandom_range(8));
    else if (r < 40) return 13'($urandom);
    else if (r < 65) return 13'(13'h0800 + $urandom_range(2047));
    else if (r < 90) return 13'(13'h1000 + $urandom_range(2047));
    else begin
      int e[8] = '{7, 8, 13'h7FF, 13'h800, 13'hFFF, 13'h1000, 13'h17FF, 13'h1FFF};
      return 13'(e[$urandom_range(7)]);
    end
  endfunction

  function automatic logic [31:0] rnd_val(input logic [12:0] a);
    int c[8] = '{0, 1, 16, 17, 512, 513, 1023, 31};
    if (a == 13'd2 || a == 13'd3) begin
      if ($urandom_range(2) == 0) return 32'($urandom);
      return 32'(c[$urandom_range(7)]);
    end
    return $urandom;
  endfunction

  task automatic t_random(input int n);
    logic [12:0] a;
    logic [31:0] d;
    logic [3:0]  be;
    bit          rdone;
    int          op;
    for (int i = 0; i < n; i++) begin
      op = $urandom_range(9);
      a  = rnd_addr();
      if (op < 3 && $urandom_range(3) == 0) a = 13'd0;     // more CTRL traffic
      d  = rnd_val(a);
      be = ($urandom_range(2) == 0) ? 4'(($urandom)) : 4'hF;
      rdone = m_busy && ($urandom_range(11) == 0);
      if (a == 13'd0 && op < 5) d[0] = ($urandom_range(3) != 0);
      if (op < 5)      tick(a, 1'b1, 1'b0, d, be, rdone);
      else if (op < 9) tick(a, 1'b0, 1'b1, d, be, rdone);
      else             tick(a, 1'b0, 1'b0, d, be, rdone);
      if (m_busy && $urandom_range(500) == 0) begin
        // reset in the middle of a run, with a read in flight
        rd(13'd5);
        c_rst_mid++;
        do_reset(1 + $urandom_range(2));
      end
    end
    if (m_busy) finish_run();
    idle(); idle();
  endtask

  task automatic t_reset_mid();
    do_reset(2);
    cfg(10, 2, 7);
    do_start();
    repeat (4) idle();
    rd(13'd5);
    #3 rst_n = 1'b0;                              // async reset between edges, read in flight
    #1;
    reset_model();
    check(acc_readdata === 32'd0 && status_busy === 0 && start === 0, "async reset mid-run");
    @(negedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    rd_chk(13'd5, 32'd0, "CYCLE_CNT after reset");
    rd_chk(13'd2, 32'd0, "LEN after reset");
    c_rst_mid++;
  endtask

  initial begin
    n_err = 0; n_chk = 0; tick_no = 0;
    c_start_ok = 0; c_start_bad = 0; c_start_busy = 0; c_start_rd = 0; c_start_rdone = 0;
    c_start_after = 0; c_rd_csr = 0; c_rd_x = 0; c_rd_y = 0; c_rd_undef = 0; c_b2b = 0;
    c_wr_busy_ign = 0; c_xwr = 0; c_cyc_hold = 0; c_rst_mid = 0;
    reset_model();
    rst_n = 1'b0; acc_addr = '0; acc_write = 0; acc_read = 0; acc_writedata = '0;
    acc_byteenable = '0; run_done = 0;
    $display("tb_smx_csr: P=%0d N_SEG=%0d BANKS=%0d ACC_RD_LAT=%0d", P, N_SEG, BANKS, smx_pkg::ACC_RD_LAT);
    if (smx_pkg::ACC_RD_LAT != 2) begin
      $display("ERROR: testbench pipeline assumes ACC_RD_LAT = 2");
      n_err++;
    end
    repeat (3) @(negedge clk);
    t_reset_values();
    t_hw_param();
    t_valid_start();
    t_invalid_start();
    t_start_busy();
    t_regs();
    t_read_path();
    t_reset_mid();
    do_reset(2);
    t_random(40000);
    idle(); idle();

    // the stimulus must really have reached every corner
    check(c_start_ok > 20 && c_start_bad > 20 && c_start_busy > 10 && c_start_rdone > 0, "coverage: starts");
    check(c_rd_csr > 100 && c_rd_x > 100 && c_rd_y > 100 && c_rd_undef > 20 && c_b2b > 100, "coverage: reads");
    check(c_xwr > 100 && c_wr_busy_ign > 5 && c_cyc_hold > 10 && c_rst_mid > 0, "coverage: writes");

    if (n_err == 0)
      $display("TB_RESULT: PASS  P=%0d N_SEG=%0d  %0d checks, starts ok/bad/busy/rdone=%0d/%0d/%0d/%0d, reads csr/x/y/undef=%0d/%0d/%0d/%0d, x_wr=%0d",
               P, N_SEG, n_chk, c_start_ok, c_start_bad, c_start_busy, c_start_rdone,
               c_rd_csr, c_rd_x, c_rd_y, c_rd_undef, c_xwr);
    else
      $display("TB_RESULT: FAIL  P=%0d N_SEG=%0d  errors=%0d of %0d checks", P, N_SEG, n_err, n_chk);
    $finish;
  end

endmodule
