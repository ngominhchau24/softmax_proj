// tb_smx_dv_corner.sv - DV test 7: arithmetic corners of smx_core (simulation only).
//
// Vectors come from model/vec_dv_corner.py; every run is named after its scenario:
//   sum_min    row sum at its lower bound 2^14, Rcp at its maximum 2^26 (REQ-ARI-06)
//   sum_max    row sum at its upper bound 2^24: K = 0 at L_MAX (REQ-ARI-05)
//   dm_max     the running maximum jumps by 254 in a group after the first (REQ-ARI-05)
//   len_sweep  every row length from 1 to L_MAX (REQ-FUN-02)
// The sum values themselves are asserted by the generator with the golden model. This test checks
// what it can see without redoing the arithmetic, the shape of the rows, then runs every vector
// and compares Y bit-exact (REQ-VER-01). At the end each scenario and each of the L_MAX lengths
// must have been run, or the test fails.
// Run from sim/:  make testname=tb_smx_dv_corner [P=8] [N_SEG=8]
`timescale 1ns/1ps

module tb_smx_dv_corner;

  parameter int P     = 8;
  parameter int N_SEG = 8;

  import smx_dv_pkg::*;

  smx_dv_env #(.P(P), .N_SEG(N_SEG)) env ();

  // ---- coverage ----
  bit seen_len [L_MAX + 1];            // len_sweep: index = L
  int n_sum_min = 0, n_sum_max = 0;
  bit dm_first, dm_last, dm_full;      // dm_max: 127 in group 1, in the last group, at L_MAX

  // index of the single 127 in row r when every other element is -128; -1 if the row is not so
  function automatic int hot_index(input int r);
    int pos, v;
    pos = -1;
    for (int i = 0; i < env.sb.L; i++) begin
      v = $signed(env.sb.q[r * L_MAX + i]);
      if (v == 127) begin
        if (pos >= 0) return -1;
        pos = i;
      end else if (v != -128) return -1;
    end
    return pos;
  endfunction

  task automatic check_shape_and_sample();
    int pos, g, n_grp;
    n_grp = env.groups(env.sb.L);
    if (env.sb.name == "sum_min") begin
      n_sum_min++;
    end else if (env.sb.name == "sum_max") begin
      if (env.sb.K != 0 || env.sb.L != L_MAX)
        env.sb.fail($sformatf("sum_max needs K = 0 and L = %0d", L_MAX));
      else n_sum_max++;
    end else if (env.sb.name == "dm_max") begin
      if (env.sb.K != 65535) env.sb.fail("dm_max needs K = 65535");
      for (int r = 0; r < env.sb.R; r++) begin
        pos = hot_index(r);
        g   = pos / P;
        if (pos < P) env.sb.fail($sformatf("dm_max row %0d: no single 127 after the first group", r));
        else begin
          if (g == 1)         dm_first = 1'b1;
          if (g == n_grp - 1) dm_last  = 1'b1;
          if (env.sb.L == L_MAX) dm_full = 1'b1;
        end
      end
    end else if (env.sb.name == "len_sweep") begin
      seen_len[env.sb.L] = 1'b1;
    end else begin
      env.sb.fail($sformatf("unknown scenario name %s", env.sb.name));
    end
  endtask

  initial begin
    bit ok;
    int n_len;

    env.init("tb_smx_dv_corner", "dv.hex");

    env.sb.next_run(ok);
    while (ok) begin
      check_shape_and_sample();
      // alternate the two ways of writing a partial last group (REQ-FUN-03)
      env.x_mode = (env.sb.L % P != 0 && env.sb.L % 2 == 1) ? 1 : 0;
      env.run_and_check();
      env.sb.next_run(ok);
    end

    env.sb.ctx = "coverage";
    n_len = 0;
    for (int l = 1; l <= L_MAX; l++) begin
      if (seen_len[l]) n_len++;
      else env.sb.fail($sformatf("row length %0d was not run", l));
    end
    env.sb.n_check += 5;
    if (n_sum_min < 2) env.sb.fail("fewer than two sum_min runs");
    if (n_sum_max < 1) env.sb.fail("no sum_max run");
    if (!dm_first)     env.sb.fail("dm_max never had the 127 in group 1");
    if (!dm_last)      env.sb.fail("dm_max never had the 127 in the last group");
    if (!dm_full)      env.sb.fail("dm_max was not run at L_MAX");

    env.finish($sformatf("%0d runs, %0d/%0d row lengths, %0d sum_min, %0d sum_max, dm_max in the first and last group",
                         env.n_runs_done, n_len, L_MAX, n_sum_min, n_sum_max));
  end

endmodule
