// tb_smx_dv_proto.sv - DV test 3: control protocol of smx_core (simulation only).
//
// Drives the situations of REQ-VER-03, REQ-FUN-04 and REQ-IF-09; the bound checker
// tb/dv/smx_core_chk.sv judges every cycle, and this test adds the end-to-end checks.
//   1. START with LEN or ROWS out of range: no run, DONE = 1 and ERR = 1, CYCLE_CNT = 0;
//      the next legal run clears ERR
//   2. START while BUSY, written in the first, second, middle, next-to-last and last BUSY cycle:
//      ignored, the run takes the same number of cycles and gives the same Y
//   3. START in the first cycle of DONE, without reprogramming: a new run, same Y
//   4. writes to LEN, ROWS, SCALE_K, X_BUF, Y_BUF, STATUS, CYCLE_CNT while BUSY: no effect;
//      STATUS and CYCLE_CNT read correctly while BUSY
// Vectors: model/vec_dv_proto.py (run 0 short, runs 1 and 2 long).
// Run from sim/:  make testname=tb_smx_dv_proto [P=8] [N_SEG=8]
`timescale 1ns/1ps

module tb_smx_dv_proto;

  parameter int P     = 8;
  parameter int N_SEG = 8;

  import smx_dv_pkg::*;

  smx_dv_env #(.P(P), .N_SEG(N_SEG)) env ();

  int n_bad = 0, n_busy_start = 0;

  // ---- 1. START with an illegal configuration ----
  task automatic bad_start(input int len, input int rows);
    logic [31:0] d;
    env.sb.ctx = $sformatf("bad_start LEN=%0d ROWS=%0d", len, rows);
    env.bfm.write(A_LEN,  len,  4'hF);
    env.bfm.write(A_ROWS, rows, 4'hF);
    env.start_run();
    repeat (8) begin
      env.sb.check1("BUSY after a bad START", env.status_busy, 1'b0);
      env.sb.check1("DONE after a bad START", env.status_done, 1'b1);
      env.sb.check1("ERR after a bad START",  env.status_err,  1'b1);
      env.bfm.idle(1);
    end
    env.bfm.read(A_STATUS, d);
    env.sb.check32("STATUS after a bad START", d, ST_DONE | ST_ERR);
    env.bfm.read(A_CYCLE, d);
    env.sb.check32("CYCLE_CNT after a bad START", d, 32'h0);
    n_bad++;
  endtask

  // checks shared by the runs below: the run of the current vector ended like the reference run
  task automatic check_end(input int ref_cycles);
    logic [31:0] d;
    bit timed_out;
    env.wait_done(env.max_cycles(env.sb.L, env.sb.R) + 8, timed_out);
    if (timed_out) begin
      env.sb.fail("no DONE");
      env.reset_dut();
      return;
    end
    env.bfm.idle(4);                       // a wrongly accepted START would show as BUSY here
    env.sb.check1("BUSY after the run", env.status_busy, 1'b0);
    env.sb.check1("DONE after the run", env.status_done, 1'b1);
    env.sb.check1("ERR after the run",  env.status_err,  1'b0);
    env.sb.check32("BUSY cycles against the undisturbed run", env.busy_cnt, ref_cycles);
    env.bfm.read(A_CYCLE, d);
    env.sb.check32("CYCLE_CNT against the undisturbed run", d, ref_cycles);
    env.check_y();
  endtask

  // ---- 2. an extra START in BUSY cycle 'at' (1 = the first BUSY cycle) ----
  task automatic start_while_busy(input int at, input int ref_cycles);
    string base;
    base = env.sb.ctx;
    env.sb.ctx = {base, $sformatf(" START in BUSY cycle %0d of %0d", at, ref_cycles)};
    env.program_run();
    env.start_run();
    env.bfm.idle(at - 1);
    env.sb.check1("BUSY when the extra START is written", env.status_busy, 1'b1);
    env.bfm.write(A_CTRL, 32'h1, 4'hF);
    check_end(ref_cycles);
    n_busy_start++;
    env.sb.ctx = base;
  endtask

  // ---- 4. bus traffic while BUSY ----
  task automatic traffic_while_busy(input int ref_cycles);
    logic [31:0] d, x0;
    string base;
    int want;
    base = env.sb.ctx;
    env.sb.ctx = {base, " writes while BUSY"};
    env.x_mode = 0;
    env.program_run();
    for (int b = 0; b < 4; b++) x0[b*8 +: 8] = env.sb.q[b];     // word 0 of row 0, L >= 4
    env.start_run();
    env.bfm.idle(2);
    // all of these must be ignored
    env.bfm.write(A_LEN,     32'd5,                  4'hF);
    env.bfm.write(A_ROWS,    32'd1,                  4'hF);
    env.bfm.write(A_SCALE_K, ~env.sb.K,              4'hF);
    env.bfm.write(A_XBUF,     32'h7F7F_7F7F,         4'hF);
    env.bfm.write(A_XBUF + 1, 32'h8080_8080,         4'hF);
    env.bfm.write(A_YBUF,     32'hDEAD_BEEF,         4'hF);
    env.bfm.write(A_STATUS,   32'hFFFF_FFFF,         4'hF);
    env.bfm.write(A_CYCLE,    32'hFFFF_FFFF,         4'hF);
    // STATUS and CYCLE_CNT are safe to read while BUSY (REQ-IF-09)
    env.sb.check1("BUSY while reading STATUS", env.status_busy, 1'b1);
    env.bfm.read(A_STATUS, d);
    env.sb.check32("STATUS read while BUSY", d, ST_BUSY);
    want = env.busy_cnt;                    // BUSY cycles completed when the read is issued
    env.bfm.read(A_CYCLE, d);
    env.sb.check32("CYCLE_CNT read while BUSY", d, want);
    env.sb.check1("still BUSY after the reads", env.status_busy, 1'b1);
    check_end(ref_cycles);
    env.bfm.read(A_LEN, d);      env.sb.check32("LEN after writes while BUSY",     d, env.sb.L);
    env.bfm.read(A_ROWS, d);     env.sb.check32("ROWS after writes while BUSY",    d, env.sb.R);
    env.bfm.read(A_SCALE_K, d);  env.sb.check32("SCALE_K after writes while BUSY", d, env.sb.K);
    env.bfm.read(A_XBUF, d);     env.sb.check32("X_BUF word 0 after writes while BUSY", d, x0);
    env.sb.ctx = base;
  endtask

  initial begin
    bit ok, timed_out;
    int ref_cycles;

    env.init("tb_smx_dv_proto", "dv.hex");

    // ---- 1 ----
    bad_start(0, 1);
    bad_start(L_MAX + 1, 1);
    bad_start(1023, 2);
    bad_start(1, 0);
    bad_start(1, R_MAX + 1);
    bad_start(1, 31);
    bad_start(0, 0);
    env.sb.next_run(ok);                    // short run: ERR must clear, result must be right
    if (ok) env.run_and_check();

    // ---- 2 and 3 ----
    env.sb.next_run(ok);
    if (ok) begin
      env.run_and_check();                  // undisturbed reference
      ref_cycles = env.busy_cnt;
      start_while_busy(1,              ref_cycles);
      start_while_busy(2,              ref_cycles);
      start_while_busy(ref_cycles / 2, ref_cycles);
      start_while_busy(ref_cycles - 1, ref_cycles);
      start_while_busy(ref_cycles,     ref_cycles);     // the last BUSY cycle

      env.sb.ctx = {env.sb.ctx, " START in the first DONE cycle"};
      env.program_run();
      env.start_run();
      env.wait_done(env.max_cycles(env.sb.L, env.sb.R) + 8, timed_out);
      env.start_run();                      // DONE just seen: this START is legal, no reprogramming
      env.sb.check1("BUSY after START in the first DONE cycle", env.status_busy, 1'b1);
      env.sb.check1("DONE after START in the first DONE cycle", env.status_done, 1'b0);
      check_end(ref_cycles);
    end

    // ---- 4 ----
    env.sb.next_run(ok);
    if (ok) begin
      env.run_and_check();
      ref_cycles = env.busy_cnt;
      traffic_while_busy(ref_cycles);
    end

    // the situations must really have happened, as seen by the checker
    env.sb.ctx = "coverage";
    env.sb.n_check += 2;
    if (env.dut.u_dv_chk.n_start_bad < n_bad || n_bad < 7)
      env.sb.fail($sformatf("checker saw %0d bad STARTs, test made %0d", env.dut.u_dv_chk.n_start_bad, n_bad));
    if (env.dut.u_dv_chk.n_start_busy < n_busy_start || n_busy_start < 5)
      env.sb.fail($sformatf("checker saw %0d STARTs while BUSY, test made %0d",
                            env.dut.u_dv_chk.n_start_busy, n_busy_start));

    env.finish($sformatf("%0d bad STARTs, %0d STARTs while BUSY, %0d vector runs",
                         n_bad, n_busy_start, env.n_runs_done));
  end

endmodule
