// smx_dv_env.sv - DV environment around smx_core (simulation only).
//
// Holds the clock, reset, DUT, acc_* BFM and scoreboard, plus the software-like sequences every
// test uses (requirements 5.3): program a run, START, wait for DONE, read back and compare.
// A testcase is a small top module that instantiates this one and calls its tasks:
//   smx_dv_env #(.P(P), .N_SEG(N_SEG)) env ();
//   initial begin env.init("tb_smx_dv_xxx", "xxx.hex"); ... env.finish("..."); end
// The DUT is driven only through acc_*; the status pins are observed as the conduit of REQ-IF-10.
// Plusarg: +VECDIR=<dir> (set by sim/Makefile).
`timescale 1ns/1ps

module smx_dv_env #(
  parameter int P     = 8,
  parameter int N_SEG = 8
) ();

  import smx_dv_pkg::*;

  logic        clk   = 1'b0;
  logic        rst_n = 1'b0;
  logic [12:0] acc_addr;
  logic        acc_write, acc_read;
  logic [31:0] acc_writedata;
  logic [3:0]  acc_byteenable;
  logic [31:0] acc_readdata;
  logic        status_busy, status_done, status_err;

  always #5 clk = ~clk;

  smx_acc_bfm bfm (
    .clk            (clk),
    .acc_addr       (acc_addr),
    .acc_write      (acc_write),
    .acc_writedata  (acc_writedata),
    .acc_byteenable (acc_byteenable),
    .acc_read       (acc_read),
    .acc_readdata   (acc_readdata)
  );

  smx_core #(.P(P), .N_SEG(N_SEG)) dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .acc_addr       (acc_addr),
    .acc_write      (acc_write),
    .acc_writedata  (acc_writedata),
    .acc_byteenable (acc_byteenable),
    .acc_read       (acc_read),
    .acc_readdata   (acc_readdata),
    .status_busy    (status_busy),
    .status_done    (status_done),
    .status_err     (status_err)
  );

  smx_scoreboard sb ();

  // protocol checker of REQ-VER-03, bound into the DUT as dut.u_dv_chk
  smx_core_bind u_bind ();

  string testname = "tb_smx_dv";
  string vecdir;
  string vcdfile;
  bit    mon_en   = 1'b0;
  int    n_runs_done = 0;

  // ---- always-on monitor of the status conduit ----
  always @(posedge clk) begin
    if (mon_en && rst_n) begin
      if ($isunknown({status_busy, status_done, status_err})) sb.fail("X or Z on a status pin");
      else if (status_busy && status_done) sb.fail("BUSY and DONE both 1");
    end
  end

  // ---- BUSY cycles of the current run, seen on the pin; start_run clears it ----
  int busy_cnt = 0;
  always @(posedge clk) if (status_busy === 1'b1) busy_cnt++;

  function automatic int groups(input int len);
    return (len + P - 1) / P;
  endfunction

  // upper bound of CYCLE_CNT from REQ-PRF-03: each row takes at most 2*ceil(L/P) + 64 cycles.
  // One more cycle because BUSY rises one cycle before the first row starts (05-cross-block.md 5).
  function automatic int max_cycles(input int len, input int rows);
    return rows * (2 * groups(len) + ROW_LAT_SLACK) + 1;
  endfunction

  // ---- reset: asserted for 3 cycles, released at a falling edge ----
  task automatic reset_dut();
    rst_n = 1'b0;
    bfm.idle(3);
    rst_n = 1'b1;
    bfm.idle(1);
  endtask

  // ---- reproducible random numbers: the same on every simulator for a given +SEED ----
  int          seed = 1;
  int unsigned rng_state = 1;
  function automatic int unsigned rnd();
    rng_state = rng_state * 32'd1664525 + 32'd1013904223;
    return rng_state >> 8;
  endfunction

  // first call of every test; vecfile = "" for a test without vectors
  task automatic init(input string name, input string vecfile);
    testname = name;
    if (!$value$plusargs("VECDIR=%s", vecdir)) vecdir = ".";
    if (!$value$plusargs("SEED=%d", seed)) seed = 1;
    rng_state = seed;
    $display("%s: P=%0d N_SEG=%0d SEED=%0d VECDIR=%s", testname, P, N_SEG, seed, vecdir);
    // +VCD=<file>: dump the DUT ports, for the waveform figures of the report (make run VCD=1)
    if ($value$plusargs("VCD=%s", vcdfile)) begin
      $dumpfile(vcdfile);
      $dumpvars(0, clk, rst_n, acc_addr, acc_write, acc_writedata, acc_byteenable, acc_read,
                acc_readdata, status_busy, status_done, status_err);
    end
    if (vecfile != "") sb.open_vectors({vecdir, "/", vecfile});
    @(negedge clk);
    reset_dut();
    mon_en = 1'b1;
  endtask

  // last call of every test
  task automatic finish(input string summary);
    sb.ctx = "end";
    if (dut.u_dv_chk.n_err != 0)
      sb.fail($sformatf("protocol checker reported %0d errors", dut.u_dv_chk.n_err));
    $display("%s: checker saw %0d START, %0d while BUSY, %0d with bad LEN/ROWS, %0d reads checked for X",
             testname, dut.u_dv_chk.n_start, dut.u_dv_chk.n_start_busy, dut.u_dv_chk.n_start_bad,
             dut.u_dv_chk.n_rd_chk);
    sb.report(testname, P, N_SEG, summary);
    $finish;
  endtask

  // ---- software steps 1-2: X_BUF rows of the scoreboard run, then LEN, ROWS, SCALE_K ----
  // x_mode selects how X_BUF is written. Elements at i >= L must not matter (REQ-FUN-03):
  //   0  like software: ceil(L/4) whole words per row, the last word padded with zeros; elements
  //      past that inside the last group keep whatever X_BUF held before (X on first use)
  //   1  every word of the last group is written, and the elements at i >= L carry hostile
  //      garbage: 127 first (it would win the row maximum), then -128, then random bytes
  //   2  like software with an 8-bit pointer: one write per element, last element first, a single
  //      byte enable each, garbage on the three disabled byte lanes (REQ-IF-03, REQ-IF-07)
  int x_mode = 0;

  function automatic logic [7:0] tail_garbage(input int k);
    if (k == 0) return 8'h7F;
    if (k == 1) return 8'h80;
    return 8'(rnd());
  endfunction

  task automatic program_run();
    logic [31:0] d;
    int nw, i;
    for (int r = 0; r < sb.R; r++) begin
      if (x_mode == 2) begin
        for (int e = sb.L - 1; e >= 0; e--) begin
          d = 32'(rnd()) ^ 32'h7F80_7F80;
          d[(e % 4)*8 +: 8] = sb.q[r * L_MAX + e];
          bfm.write(A_XBUF + r * ROW_WORDS + e / 4, d, 4'(1 << (e % 4)));
        end
      end else begin
        nw = (x_mode == 1) ? groups(sb.L) * P / 4 : (sb.L + 3) / 4;
        for (int w = 0; w < nw; w++) begin
          d = '0;
          for (int b = 0; b < 4; b++) begin
            i = w*4 + b;
            if (i < sb.L)         d[b*8 +: 8] = sb.q[r * L_MAX + i];
            else if (x_mode == 1) d[b*8 +: 8] = tail_garbage(i - sb.L);
          end
          bfm.write(A_XBUF + r * ROW_WORDS + w, d, 4'hF);
        end
      end
    end
    bfm.write(A_LEN,     sb.L, 4'hF);
    bfm.write(A_ROWS,    sb.R, 4'hF);
    bfm.write(A_SCALE_K, sb.K, 4'hF);
  endtask

  // CYCLE_CNT of a legal run by the formula of the spec (REQ-VER-04)
  function automatic int spec_cycles(input int len, input int rows);
    return rows * (2 * groups(len) + ROW_OVERHEAD_SPEC) + 1;
  endfunction

  // ---- software step 3: returns in the cycle right after the START write ----
  task automatic start_run();
    busy_cnt = 0;
    bfm.write(A_CTRL, 32'h1, 4'hF);
  endtask

  // ---- software step 4, on the pin: returns at the first falling edge where DONE is 1 ----
  task automatic wait_done(input int limit, output bit timed_out);
    int n;
    n = 0;
    timed_out = 1'b0;
    while (status_done !== 1'b1 && !timed_out) begin
      if (n >= limit) timed_out = 1'b1;
      else begin
        @(negedge clk);
        n++;
      end
    end
  endtask

  // ---- software step 5: read Y_BUF and compare every element i < L with the golden model ----
  task automatic check_y();
    logic [7:0] got, want;
    int nw, i;
    nw = (sb.L + 3) / 4;
    for (int r = 0; r < sb.R; r++) begin
      bfm.read_burst(A_YBUF + r * ROW_WORDS, nw);
      for (int w = 0; w < nw; w++) begin
        for (int b = 0; b < 4; b++) begin
          i = w*4 + b;
          if (i < sb.L) begin
            got  = bfm.rbuf[w][b*8 +: 8];
            want = sb.y[r * L_MAX + i];
            sb.n_check++;
            if (got !== want)
              sb.fail($sformatf("Y[r=%0d][i=%0d] = %h, want %h", r, i, got, want));
          end
        end
      end
    end
  endtask

  // ---- the whole sequence for the current scoreboard run, with the checks every run must pass ----
  task automatic run_and_check();
    logic [31:0] d;
    bit timed_out;
    int limit;
    limit = max_cycles(sb.L, sb.R);
    program_run();
    start_run();
    // START was sampled in the previous cycle: BUSY must be up now, DONE and ERR cleared
    sb.check1("BUSY in the cycle after START", status_busy, 1'b1);
    sb.check1("DONE in the cycle after START", status_done, 1'b0);
    sb.check1("ERR in the cycle after START",  status_err,  1'b0);
    wait_done(limit + 8, timed_out);
    if (timed_out) begin
      sb.fail($sformatf("no DONE after %0d cycles (REQ-PRF-03 allows %0d)", limit + 8, limit));
      reset_dut();
      return;
    end
    sb.check1("BUSY when DONE is seen", status_busy, 1'b0);
    sb.check1("ERR after a legal run",  status_err,  1'b0);
    bfm.read(A_STATUS, d);
    sb.check32("STATUS after the run", d, ST_DONE);
    bfm.read(A_CYCLE, d);
    sb.check32("CYCLE_CNT against BUSY cycles seen on the pin", d, busy_cnt);
    sb.n_check++;
    if (busy_cnt > limit)
      sb.fail($sformatf("run took %0d cycles, REQ-PRF-03 allows %0d", busy_cnt, limit));
    check_y();
    n_runs_done++;
  endtask

  // ---- watchdog ----
  initial begin
    #2s;
    $display("TB_RESULT: FAIL %s watchdog", testname);
    $finish;
  end

endmodule
