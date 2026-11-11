// tb_smx_dv_random.sv - DV test 6: random runs, history independence and reset in mid-run.
//
// Vectors: model/vec_dv_random.py, random L, R, K and row statistics for the given SEED.
//   pass A  every run once, X_BUF written in a randomly chosen way (REQ-VER-01)
//   pass B  the same runs again in the same order. The core now carries the history of pass A and
//           the buffers hold other rows, yet Y must be the same (REQ-FUN-05). Every third run is
//           first started with a wrong SCALE_K and aborted by an asynchronous reset at a random
//           BUSY cycle; after the reset the registers must read 0, nothing may run by itself, and
//           the real run must overwrite everything the aborted one left in Y_BUF.
// Run from sim/:  make testname=tb_smx_dv_random [P=8] [N_SEG=8] [SEED=1]
`timescale 1ns/1ps

module tb_smx_dv_random;

  parameter int P     = 8;
  parameter int N_SEG = 8;

  import smx_dv_pkg::*;

  smx_dv_env #(.P(P), .N_SEG(N_SEG)) env ();

  int n_resets = 0;

  // start the current run with a wrong K, then reset in BUSY cycle 'at'
  task automatic abort_by_reset(input int at);
    logic [31:0] d;
    string base;
    base = env.sb.ctx;
    env.sb.ctx = {base, $sformatf(" reset in BUSY cycle %0d", at)};
    env.program_run();
    env.bfm.write(A_SCALE_K, env.sb.K ^ 32'h0000_5A5A, 4'hF);
    env.start_run();
    env.bfm.idle(at - 1);
    env.sb.check1("BUSY right before the reset", env.status_busy, 1'b1);
    #3;                                     // between clock edges: the reset is asynchronous
    env.rst_n = 1'b0;
    #1;
    env.sb.check1("BUSY during reset", env.status_busy, 1'b0);
    env.sb.check1("DONE during reset", env.status_done, 1'b0);
    env.sb.check1("ERR during reset",  env.status_err,  1'b0);
    @(negedge env.clk);
    @(negedge env.clk);
    env.rst_n = 1'b1;                       // released at a falling edge
    env.bfm.idle(1);
    env.bfm.read(A_STATUS, d);   env.sb.check32("STATUS after reset",    d, 32'h0);
    env.bfm.read(A_LEN, d);      env.sb.check32("LEN after reset",       d, 32'h0);
    env.bfm.read(A_ROWS, d);     env.sb.check32("ROWS after reset",      d, 32'h0);
    env.bfm.read(A_SCALE_K, d);  env.sb.check32("SCALE_K after reset",   d, 32'h0);
    env.bfm.read(A_CYCLE, d);    env.sb.check32("CYCLE_CNT after reset", d, 32'h0);
    repeat (20) begin
      env.bfm.idle(1);
      if (env.status_busy !== 1'b0 || env.status_done !== 1'b0)
        env.sb.fail("the core ran by itself after reset");
    end
    env.sb.n_check++;
    n_resets++;
    env.sb.ctx = base;
  endtask

  initial begin
    bit ok;
    int k, total;

    env.init("tb_smx_dv_random", "dv.hex");

    // ---- pass A ----
    env.sb.next_run(ok);
    while (ok) begin
      env.x_mode = env.rnd() % 3;
      env.sb.ctx = {env.sb.ctx, $sformatf(" passA x_mode=%0d", env.x_mode)};
      env.run_and_check();
      env.sb.next_run(ok);
    end

    // ---- pass B ----
    env.sb.open_vectors({env.vecdir, "/dv.hex"});
    k = 0;
    env.sb.next_run(ok);
    while (ok) begin
      env.x_mode = env.rnd() % 3;
      env.sb.ctx = {env.sb.ctx, $sformatf(" passB x_mode=%0d", env.x_mode)};
      if (k % 3 == 0) begin
        total = env.spec_cycles(env.sb.L, env.sb.R);
        abort_by_reset(1 + env.rnd() % (total - 1));
      end
      env.run_and_check();
      k++;
      env.sb.next_run(ok);
    end

    env.sb.ctx = "coverage";
    env.sb.n_check++;
    if (n_resets == 0) env.sb.fail("no reset in mid-run was exercised");

    env.finish($sformatf("%0d runs in two passes, %0d resets in mid-run, seed %0d",
                         env.n_runs_done, n_resets, env.seed));
  end

endmodule
