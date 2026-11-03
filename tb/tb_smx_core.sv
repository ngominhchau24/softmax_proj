// tb_smx_core.sv - self-checking testbench for smx_core (simulation only).
//
// Drives only the acc_* port, like software would (requirements 5.3), and respects read latency 2.
// Expected values come from model/vec_core.py -> softmax_ref.softmax_row (file core.hex; format in
// the header of vec_core.py). The same bench also exercises smx_delay (no separate test).
// Convention: every command is driven at a falling clock edge; a read issued at falling edge T0
// returns acc_readdata at falling edge T0+2 (ACC_RD_LAT).
// Prints one "TB_RESULT: PASS" or "TB_RESULT: FAIL" line.
// Plusargs: +VECDIR=<dir> (default tb/vectors/smx_core/p<P>_n<N_SEG>)
`timescale 1ns/1ps

module tb_smx_core;

  parameter int P     = smx_pkg::P;
  parameter int N_SEG = smx_pkg::N_SEG;

  localparam int LMAX     = smx_pkg::L_MAX;
  localparam int RMAX     = smx_pkg::R_MAX;
  localparam int ROWWORDS = LMAX / 4;           // words per row in X_BUF / Y_BUF
  localparam int BUFWORDS = RMAX * ROWWORDS;
  localparam int MAX_MSG  = 20;
  localparam int A_CTRL = 0, A_STATUS = 1, A_LEN = 2, A_ROWS = 3, A_K = 4, A_CYC = 5, A_HW = 6;
  localparam int A_XBUF = 13'h800, A_YBUF = 13'h1000;

  logic        clk = 1'b0;
  logic        rst_n;
  logic [12:0] acc_addr;
  logic        acc_write, acc_read;
  logic [31:0] acc_writedata;
  logic [3:0]  acc_byteenable;
  logic [31:0] acc_readdata;
  logic        status_busy, status_done, status_err;

  always #5 clk = ~clk;

  smx_core #(.P(P), .N_SEG(N_SEG)) dut (.*);

  // ---- bookkeeping ----
  int    n_err   = 0;
  int    n_check = 0;          // Y bytes compared
  int    n_xseen = 0;          // unwritten X_BUF bytes read back as X
  int    n_runs_done = 0;
  string vecdir;
  string cur;
  bit    mon_en = 1'b0;

  task automatic report(input string msg);
    n_err++;
    if (n_err <= MAX_MSG) $display("ERROR [%s] %s", cur, msg);
  endtask

  // ---- status monitor: BUSY and DONE never together, no X once out of reset ----
  always @(posedge clk) begin
    if (mon_en && rst_n) begin
      if ($isunknown({status_busy, status_done, status_err})) report("X on status pins");
      else if (status_busy && status_done) report("BUSY and DONE both 1");
    end
  end

  // ---- vector storage ----
  int           n_runs;
  int           run_L[], run_R[], run_K[], run_fl[];
  logic [7:0]   run_q[][];      // R*L bytes, row-major
  logic [7:0]   run_y[][];

  function automatic int hexval(input byte c);
    if (c >= "0" && c <= "9") return c - "0";
    if (c >= "a" && c <= "f") return c - "a" + 10;
    return c - "A" + 10;
  endfunction

  task automatic load_vectors();
    int    fd, k, r, L, R, K, fl;
    string line, tag, hs;
    fd = $fopen({vecdir, "/core.hex"}, "r");
    if (fd == 0) begin
      $display("ERROR: cannot open %s/core.hex (run model/gen_vectors.py core)", vecdir);
      n_err++;
      n_runs = 0;
      return;
    end
    n_runs = 0;
    while ($fgets(line, fd) != 0) begin
      if (line.len() < 2 || line[0] == "#") continue;
      if ($sscanf(line, "NRUNS %d", n_runs) == 1) begin
        run_L = new[n_runs]; run_R = new[n_runs]; run_K = new[n_runs]; run_fl = new[n_runs];
        run_q = new[n_runs]; run_y = new[n_runs];
        break;
      end
    end
    for (k = 0; k < n_runs; k++) begin
      while ($fgets(line, fd) != 0 && (line.len() < 2 || line[0] == "#")) ;
      if ($sscanf(line, "RUN %d %d %d %d", L, R, K, fl) != 4) begin
        $display("ERROR: bad RUN line %s", line);
        n_err++;
        return;
      end
      run_L[k] = L; run_R[k] = R; run_K[k] = K; run_fl[k] = fl;
      run_q[k] = new[R*L];
      run_y[k] = new[R*L];
      for (r = 0; r < R; r++) begin
        void'($fgets(line, fd));
        void'($sscanf(line, "%s %s", tag, hs));
        for (int i = 0; i < L; i++) run_q[k][r*L+i] = 8'((hexval(hs[2*i]) << 4) | hexval(hs[2*i+1]));
      end
      for (r = 0; r < R; r++) begin
        void'($fgets(line, fd));
        void'($sscanf(line, "%s %s", tag, hs));
        for (int i = 0; i < L; i++) run_y[k][r*L+i] = 8'((hexval(hs[2*i]) << 4) | hexval(hs[2*i+1]));
      end
    end
    $fclose(fd);
  endtask

  // ---- acc_* primitives ----
  task automatic cmd_write(input int addr, input logic [31:0] data, input logic [3:0] be);
    acc_addr = 13'(addr); acc_write = 1'b1; acc_read = 1'b0;
    acc_writedata = data; acc_byteenable = be;
    @(negedge clk);
    acc_write = 1'b0;
  endtask

  task automatic idle(input int n);
    acc_write = 1'b0; acc_read = 1'b0;
    repeat (n) @(negedge clk);
  endtask

  logic [31:0] rbuf [BUFWORDS];

  // cnt reads at consecutive cycles, one per cycle; rbuf[j] is the data of read j
  task automatic rd_burst(input int addr, input int cnt);
    for (int i = 0; i <= cnt; i++) begin
      if (i < cnt) begin
        acc_addr = 13'(addr + i); acc_read = 1'b1; acc_write = 1'b0;
      end else acc_read = 1'b0;
      @(negedge clk);
      if (i >= 1) rbuf[i-1] = acc_readdata;
    end
  endtask

  task automatic rd1(input int addr, output logic [31:0] d);
    rd_burst(addr, 1);
    d = rbuf[0];
  endtask

  // ---- X_BUF shadow: X until written, byte accurate ----
  logic [31:0] xs [BUFWORDS];

  task automatic wr_x(input int w, input logic [31:0] data, input logic [3:0] be);
    cmd_write(A_XBUF + w, data, be);
    for (int b = 0; b < 4; b++) if (be[b]) xs[w][b*8 +: 8] = data[b*8 +: 8];
  endtask

  function automatic logic [7:0] garbage();
    case ($urandom % 4)
      0: return 8'd127;
      1: return 8'h80;
      default: return 8'($urandom);
    endcase
  endfunction

  function automatic int groups(input int L);
    return (L + P - 1) / P;
  endfunction

  // ---- program one run: LEN, ROWS, SCALE_K, X_BUF ----
  task automatic program_run(input int k);
    int L, R, G, wr_words;
    logic [31:0] d;
    logic [3:0]  be;
    int i;
    L = run_L[k]; R = run_R[k]; G = groups(L);
    wr_words = G * P / 4;
    cmd_write(A_LEN,  32'(L),     4'hF);
    cmd_write(A_ROWS, 32'(R),     4'hF);
    cmd_write(A_K,    32'(run_K[k]), 4'hF);
    for (int r = 0; r < R; r++) begin
      for (int w = 0; w < wr_words; w++) begin
        be = 4'h0;
        for (int b = 0; b < 4; b++) begin
          i = w*4 + b;
          if (i < L) begin d[b*8 +: 8] = run_q[k][r*L+i]; be[b] = 1'b1; end
          else begin
            d[b*8 +: 8] = garbage();
            be[b] = !run_fl[k][0];         // flag bit 0: leave the tail unwritten
          end
        end
        if (be != 4'h0) wr_x(r*ROWWORDS + w, d, be);
      end
    end
  endtask

  // ---- start and wait: statuses, busy cycle count ----
  int busy_cycles;

  // START then wait for DONE. Leaves us at the falling edge where DONE is first seen.
  task automatic start_and_wait(input int max_cycles);
    int cnt;
    cmd_write(A_CTRL, 32'd1, 4'hF);
    // now in cycle n+1: BUSY must already be up
    if (status_busy !== 1'b1 || status_done !== 1'b0 || status_err !== 1'b0)
      report($sformatf("after START: busy=%b done=%b err=%b, want 1 0 0",
                       status_busy, status_done, status_err));
    cnt = 0;
    while (status_done !== 1'b1) begin
      if (status_busy !== 1'b1) begin
        report("BUSY dropped before DONE");
        break;
      end
      cnt++;
      if (cnt > max_cycles) begin
        report("timeout waiting for DONE");
        break;
      end
      @(negedge clk);
    end
    if (status_busy !== 1'b0) report("BUSY still 1 when DONE seen");
    if (status_err !== 1'b0) report("ERR set after good run");
    busy_cycles = cnt;
  endtask

  function automatic int expect_cycles(input int L, input int R);
    return R * (2 * groups(L) + smx_pkg::ROW_OVERHEAD) + 1;
  endfunction

  // ---- check results and cycle count of run k ----
  task automatic check_run(input int k, input int n_busy);
    int L, R, G, nw, want;
    logic [31:0] d;
    logic [7:0]  got;
    L = run_L[k]; R = run_R[k]; G = groups(L);
    nw = G * P / 4;
    want = expect_cycles(L, R);
    if (n_busy != want)
      report($sformatf("busy cycles %0d, want %0d (L=%0d R=%0d)", n_busy, want, L, R));
    rd1(A_CYC, d);
    if (d !== 32'(want))
      report($sformatf("CYCLE_CNT %0d, want %0d (L=%0d R=%0d)", d, want, L, R));
    rd1(A_STATUS, d);
    if (d !== 32'h2) report($sformatf("STATUS %h after run, want 2", d));
    for (int r = 0; r < R; r++) begin
      rd_burst(A_YBUF + r*ROWWORDS, nw);
      for (int w = 0; w < nw; w++) begin
        for (int b = 0; b < 4; b++) begin
          int i = w*4 + b;
          got = rbuf[w][b*8 +: 8];
          if (i < L) begin
            n_check++;
            if (got !== run_y[k][r*L+i])
              report($sformatf("Y[r=%0d][i=%0d] = %h, want %h (L=%0d R=%0d K=%0d)",
                               r, i, got, run_y[k][r*L+i], L, R, run_K[k]));
          end else if ($isunknown(got))
            report($sformatf("Y[r=%0d][i=%0d] is X inside the last group (L=%0d)", r, i, L));
        end
      end
    end
    // X_BUF must be unchanged, X where nothing was written
    for (int r = 0; r < R; r++) begin
      rd_burst(A_XBUF + r*ROWWORDS, nw);
      for (int w = 0; w < nw; w++) begin
        if (rbuf[w] !== xs[r*ROWWORDS + w])
          report($sformatf("X_BUF word %0d = %h, shadow %h", r*ROWWORDS + w, rbuf[w], xs[r*ROWWORDS + w]));
        for (int b = 0; b < 4; b++) if ($isunknown(rbuf[w][b*8 +: 8])) n_xseen++;
      end
    end
  endtask

  task automatic do_run(input int k);
    cur = $sformatf("run%0d L=%0d R=%0d K=%0d", k, run_L[k], run_R[k], run_K[k]);
    program_run(k);
    start_and_wait(2 * expect_cycles(run_L[k], run_R[k]) + 100);
    if (busy_cycles != expect_cycles(run_L[k], run_R[k]))
      report($sformatf("busy cycles %0d, want %0d", busy_cycles, expect_cycles(run_L[k], run_R[k])));
    if (run_fl[k][1])      // same configuration again, START in the cycle right after DONE appears
      start_and_wait(2 * expect_cycles(run_L[k], run_R[k]) + 100);
    check_run(k, busy_cycles);
    n_runs_done++;
  endtask

  // ---- directed tests ----
  task automatic test_hw_param();
    logic [31:0] d, want;
    cur = "hw_param";
    want = {8'h10, 4'($clog2(N_SEG)), 8'(RMAX), 4'($clog2(LMAX)), 8'(P)};
    rd1(A_HW, d);
    if (d !== want) report($sformatf("HW_PARAM %h, want %h", d, want));
    // alternating sources back to back: every read returns exactly 2 cycles after its command
    for (int i = 0; i <= 6; i++) begin
      if (i < 6) begin
        acc_addr = (i % 2) ? 13'(A_STATUS) : 13'(A_HW);
        acc_read = 1'b1; acc_write = 1'b0;
      end else acc_read = 1'b0;
      @(negedge clk);
      if (i >= 1) begin
        want = ((i-1) % 2) ? 32'h0 : {8'h10, 4'($clog2(N_SEG)), 8'(RMAX), 4'($clog2(LMAX)), 8'(P)};
        if (acc_readdata !== want) report($sformatf("alternating read %0d: %h, want %h", i-1, acc_readdata, want));
      end
    end
    acc_read = 1'b0;
    repeat (2) @(negedge clk);
  endtask

  task automatic test_xbuf_be();
    logic [31:0] d;
    int w;
    cur = "xbuf_be";
    // rows 14..15 region, nothing else uses it before the R = 16 runs
    w = 14*ROWWORDS + 3;
    wr_x(w,     32'hA1B2C3D4, 4'hF);
    wr_x(w,     32'h11223344, 4'b0101);
    wr_x(w,     32'h55667788, 4'b1000);
    wr_x(w + 1, 32'hCAFEF00D, 4'b0010);       // three bytes stay X
    wr_x(w + 2, 32'hDEADBEEF, 4'b0000);       // no byte enabled: stays X
    wr_x(w + 5, 32'h01020304, 4'hF);
    rd_burst(A_XBUF + w, 6);
    for (int j = 0; j < 6; j++)
      if (rbuf[j] !== xs[w + j]) report($sformatf("X_BUF readback word %0d = %h, shadow %h", w + j, rbuf[j], xs[w + j]));
    if (xs[w] !== 32'h5522C344) report($sformatf("shadow literal %h, want 5522C344", xs[w]));
    if (rbuf[0] !== 32'h5522C344) report($sformatf("X_BUF literal %h, want 5522C344", rbuf[0]));
    if (!$isunknown(rbuf[1][7:0]) || rbuf[1][15:8] !== 8'hF0 || !$isunknown(rbuf[1][23:16]))
      report($sformatf("X_BUF partial word %h", rbuf[1]));
    if (!$isunknown(rbuf[2])) report("X_BUF word written with be=0 changed");
    // upper regions read back as zero: undefined area and CSR holes
    rd1(13'h07FF, d);
    if (d !== 32'h0) report("undefined word 0x7FF not 0");
    rd1(13'h1800, d);
    if (d !== 32'h0) report("undefined word 0x1800 not 0");
  endtask

  task automatic test_after_reset_regs();
    logic [31:0] d;
    int regs [5] = '{A_STATUS, A_LEN, A_ROWS, A_K, A_CYC};
    cur = "reset_regs";
    foreach (regs[j]) begin
      rd1(regs[j], d);
      if (d !== 32'h0) report($sformatf("register %0d = %h after reset, want 0", regs[j], d));
    end
  endtask

  // ERR: bad LEN or ROWS
  task automatic test_err(input int L, input int R);
    logic [31:0] d;
    cur = $sformatf("err L=%0d R=%0d", L, R);
    cmd_write(A_LEN,  32'(L), 4'hF);
    cmd_write(A_ROWS, 32'(R), 4'hF);
    cmd_write(A_CTRL, 32'd1, 4'hF);
    for (int i = 0; i < 8; i++) begin
      if (status_busy !== 1'b0 || status_done !== 1'b1 || status_err !== 1'b1)
        report($sformatf("cycle %0d after bad START: busy=%b done=%b err=%b, want 0 1 1", i, status_busy, status_done, status_err));
      @(negedge clk);
    end
    rd1(A_STATUS, d);
    if (d !== 32'h6) report($sformatf("STATUS %h after ERR, want 6", d));
    rd1(A_CYC, d);
    if (d !== 32'h0) report($sformatf("CYCLE_CNT %0d after ERR, want 0", d));
  endtask

  // reset in the middle of a run, then the same run must be correct
  task automatic test_reset_mid(input int k, input int delay);
    logic [31:0] d;
    cur = $sformatf("reset_mid run%0d after %0d cycles", k, delay);
    program_run(k);
    cmd_write(A_CTRL, 32'd1, 4'hF);
    repeat (delay) @(negedge clk);
    if (delay < expect_cycles(run_L[k], run_R[k]) - 1 && status_busy !== 1'b1)
      report("run ended before the planned reset");
    rst_n = 1'b0;
    #1;
    if (status_busy !== 1'b0 || status_done !== 1'b0 || status_err !== 1'b0)
      report("status not cleared by async reset");
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    test_after_reset_regs();
    // nothing runs by itself
    repeat (20) begin
      @(negedge clk);
      if (status_busy !== 1'b0) report("BUSY up after reset without START");
    end
    do_run(k);
  endtask

  task automatic do_reset();
    rst_n = 1'b0;
    acc_write = 1'b0; acc_read = 1'b0; acc_addr = '0; acc_writedata = '0; acc_byteenable = 4'hF;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
  endtask

  initial begin
    int rst_run;
    if (!$value$plusargs("VECDIR=%s", vecdir))
      vecdir = $sformatf("tb/vectors/smx_core/p%0d_n%0d", P, N_SEG);
    $display("tb_smx_core: P=%0d N_SEG=%0d ROW_OVERHEAD=%0d VECDIR=%s", P, N_SEG, smx_pkg::ROW_OVERHEAD, vecdir);
    cur = "init";
    rst_n = 1'b0;
    acc_write = 1'b0; acc_read = 1'b0; acc_addr = '0; acc_writedata = '0; acc_byteenable = 4'hF;
    for (int i = 0; i < BUFWORDS; i++) xs[i] = 'x;
    load_vectors();
    @(negedge clk);
    mon_en = 1'b1;
    do_reset();

    test_after_reset_regs();
    test_hw_param();
    test_xbuf_be();

    // all vector runs
    for (int k = 0; k < n_runs; k++) do_run(k);
    if (n_xseen == 0) begin
      cur = "fresh";
      report("no unwritten X_BUF element was read back as X: REQ-FUN-03 case not exercised");
    end

    // ERR path, then a good run
    test_err(0, 1);
    test_err(LMAX + 1, 1);
    test_err(1023, 2);
    test_err(1, 0);
    test_err(1, RMAX + 1);
    test_err(1, 31);
    test_err(0, 0);
    do_run(n_runs > 3 ? 3 : 0);

    // reset in the middle of a run
    rst_run = -1;
    for (int k = 0; k < n_runs; k++) if (run_fl[k][2] && rst_run < 0) rst_run = k;
    if (rst_run >= 0) begin
      int t;
      t = expect_cycles(run_L[rst_run], run_R[rst_run]);
      test_reset_mid(rst_run, 2);
      test_reset_mid(rst_run, 12);
      test_reset_mid(rst_run, t / 5);
      test_reset_mid(rst_run, t / 3);
      test_reset_mid(rst_run, t / 2);
      test_reset_mid(rst_run, t * 3 / 5);
      test_reset_mid(rst_run, t * 4 / 5);
      test_reset_mid(rst_run, t - 3);
      test_reset_mid(rst_run, t - 1);
    end else begin
      cur = "reset_mid";
      report("no run flagged for the reset test");
    end

    // last: the whole file again after all the history (REQ-FUN-05), quick subset of runs
    for (int k = 0; k < n_runs; k += 7) do_run(k);

    cur = "end";
    if (n_runs_done == 0) report("no run executed");
    if (n_err == 0)
      $display("TB_RESULT: PASS tb_smx_core P=%0d N_SEG=%0d: %0d runs, %0d Y bytes checked, %0d X bytes seen in unwritten X_BUF",
               P, N_SEG, n_runs_done, n_check, n_xseen);
    else
      $display("TB_RESULT: FAIL tb_smx_core P=%0d N_SEG=%0d: %0d errors", P, N_SEG, n_err);
    $finish;
  end

  // watchdog
  initial begin
    #200ms;
    $display("TB_RESULT: FAIL tb_smx_core watchdog");
    $finish;
  end

endmodule
