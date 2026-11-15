// tb_smx_dv_ver02.sv - DV test 2: the scenario list of REQ-VER-02 on smx_core (simulation only).
//
// Vectors come from model/vec_dv_ver02.py. Every run holds rows of one kind and is named after it.
// For each run this test
//   1. checks that the rows really are of the named kind, so the coverage below cannot be faked
//   2. runs it and compares Y bit-exact with the golden model (REQ-VER-01, REQ-FUN-01, REQ-FUN-02)
//   3. when L is not a multiple of P, runs it twice: with hostile garbage at i >= L, then again
//      like software would write it. Both must give the same Y (REQ-FUN-03)
// At the end every bin of the REQ-VER-02 list must have been hit, or the test fails:
//   kind x length for lengths 1, P-1, P, P+1, 2P+1, L_MAX (combinations that cannot exist excluded)
//   K = 0, 1, 65535      R = 1, R_MAX      L_MAX together with R_MAX
// Run from sim/:  make testname=tb_smx_dv_ver02 [P=8] [N_SEG=8]
`timescale 1ns/1ps

module tb_smx_dv_ver02;

  parameter int P     = 8;
  parameter int N_SEG = 8;

  import smx_dv_pkg::*;

  smx_dv_env #(.P(P), .N_SEG(N_SEG)) env ();

  // ---- scenario kinds, in the order of model/vec_dv_ver02.py ----
  localparam int NK = 7;
  localparam int K_ALL_MIN = 0, K_ALL_MAX = 1, K_UNIFORM = 2, K_ONEHOT_HI = 3, K_ONEHOT_LO = 4,
                 K_MAX_LAST = 5, K_RANDOM = 6;
  string kind_name [NK] = '{"all_min", "all_max", "uniform", "onehot_hi", "onehot_lo",
                            "max_last_group", "random"};

  // ---- coverage bins ----
  localparam int NL  = 6;
  localparam int NKV = 3;
  int len_bin [NL]  = '{1, P - 1, P, P + 1, 2 * P + 1, L_MAX};
  int k_bin   [NKV] = '{0, 1, 65535};
  bit seen_kl [NK][NL];
  bit seen_k  [NKV];
  bit seen_r1, seen_rmax, seen_full;
  int n_tail_pairs = 0;

  function automatic int kind_index(input string name);
    for (int k = 0; k < NK; k++) if (name == kind_name[k]) return k;
    return -1;
  endfunction

  // can a row of this kind exist at this length?
  function automatic bit applicable(input int kind, input int len);
    if (kind == K_ONEHOT_HI || kind == K_ONEHOT_LO) return len >= 2;
    if (kind == K_MAX_LAST) return len > P;
    return 1'b1;
  endfunction

  // independent check of the stimulus: is row r of the current run of this kind?
  function automatic bit row_is_kind(input int kind, input int r);
    int len, last0, v, v0, n_hi, n_lo, mx_early, mx_last;
    len   = env.sb.L;
    last0 = (env.groups(len) - 1) * P;
    v0    = $signed(env.sb.q[r * L_MAX]);
    n_hi = 0; n_lo = 0; mx_early = -129; mx_last = -129;
    for (int i = 0; i < len; i++) begin
      v = $signed(env.sb.q[r * L_MAX + i]);
      if (v == 127)  n_hi++;
      if (v == -128) n_lo++;
      if (kind == K_UNIFORM && v != v0) return 1'b0;
      if (i < last0) begin if (v > mx_early) mx_early = v; end
      else           begin if (v > mx_last)  mx_last  = v; end
    end
    case (kind)
      K_ALL_MIN:   return n_lo == len;
      K_ALL_MAX:   return n_hi == len;
      K_ONEHOT_HI: return n_hi == 1 && n_lo == len - 1;
      K_ONEHOT_LO: return n_lo == 1 && n_hi == len - 1;
      K_MAX_LAST:  return last0 > 0 && mx_last > mx_early;
      default:     return 1'b1;
    endcase
  endfunction

  task automatic sample_coverage(input int kind);
    for (int l = 0; l < NL; l++) if (env.sb.L == len_bin[l]) seen_kl[kind][l] = 1'b1;
    for (int k = 0; k < NKV; k++) if (env.sb.K == k_bin[k]) seen_k[k] = 1'b1;
    if (env.sb.R == 1)     seen_r1   = 1'b1;
    if (env.sb.R == R_MAX) seen_rmax = 1'b1;
    if (env.sb.R == R_MAX && env.sb.L == L_MAX) seen_full = 1'b1;
  endtask

  task automatic check_coverage(output int n_bins, output int n_hit);
    n_bins = 0;
    n_hit  = 0;
    env.sb.ctx = "coverage";
    for (int kind = 0; kind < NK; kind++) begin
      for (int l = 0; l < NL; l++) begin
        if (applicable(kind, len_bin[l])) begin
          n_bins++;
          if (seen_kl[kind][l]) n_hit++;
          else env.sb.fail($sformatf("bin not hit: %s at L=%0d", kind_name[kind], len_bin[l]));
        end
      end
    end
    for (int k = 0; k < NKV; k++) begin
      n_bins++;
      if (seen_k[k]) n_hit++;
      else env.sb.fail($sformatf("bin not hit: K=%0d", k_bin[k]));
    end
    n_bins += 3;
    if (seen_r1)   n_hit++; else env.sb.fail("bin not hit: R=1");
    if (seen_rmax) n_hit++; else env.sb.fail("bin not hit: R=R_MAX");
    if (seen_full) n_hit++; else env.sb.fail("bin not hit: L=L_MAX with R=R_MAX");
  endtask

  initial begin
    bit    ok;
    int    kind, n_bins, n_hit;
    string base;

    env.init("tb_smx_dv_ver02", "dv.hex");

    env.sb.next_run(ok);
    while (ok) begin
      base = env.sb.ctx;
      kind = kind_index(env.sb.name);
      if (kind < 0) begin
        env.sb.fail($sformatf("unknown scenario name %s", env.sb.name));
      end else begin
        for (int r = 0; r < env.sb.R; r++)
          if (!row_is_kind(kind, r))
            env.sb.fail($sformatf("row %0d is not of kind %s", r, env.sb.name));

        if (env.sb.L % P != 0) begin
          // partial last group: hostile tail first, then the software-like write (REQ-FUN-03)
          env.x_mode = 1;
          env.sb.ctx    = {base, " tail=garbage"};
          env.run_and_check();
          env.x_mode = 0;
          env.sb.ctx    = {base, " tail=software"};
          env.run_and_check();
          n_tail_pairs++;
        end else begin
          env.x_mode = 0;
          env.run_and_check();
        end
        sample_coverage(kind);
      end
      env.sb.next_run(ok);
    end

    check_coverage(n_bins, n_hit);
    env.finish($sformatf("%0d runs, %0d of them with both tail modes, coverage %0d/%0d bins",
                         env.n_runs_done, n_tail_pairs, n_hit, n_bins));
  end

endmodule
