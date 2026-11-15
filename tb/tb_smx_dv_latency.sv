// tb_smx_dv_latency.sv - DV test 4: CYCLE_CNT against the latency formula (REQ-VER-04).
//
// Reference: docs/spec/05-cross-block.md section 5, copied into smx_dv_pkg, not read from smx_pkg:
//   CYCLE_CNT = R * (2 * ceil(L/P) + 54) + 1
// For every run of model/vec_dv_latency.py (many L around the group boundaries, several R, three
// kinds of data per shape) this test checks
//   - CYCLE_CNT equals the formula, and so does the number of BUSY cycles seen on the pin
//   - CYCLE_CNT holds its value after DONE
//   - the latency depends on L and R only, never on the data or on K
//   - Y is bit-exact as in every other test, and REQ-PRF-03 holds (inside run_and_check)
// Run from sim/:  make testname=tb_smx_dv_latency [P=8] [N_SEG=8]
`timescale 1ns/1ps

module tb_smx_dv_latency;

  parameter int P     = 8;
  parameter int N_SEG = 8;

  import smx_dv_pkg::*;

  smx_dv_env #(.P(P), .N_SEG(N_SEG)) env ();

  initial begin
    bit ok;
    logic [31:0] d;
    int want, n_shapes, last_L, last_R, max_row;

    env.init("tb_smx_dv_latency", "dv.hex");
    n_shapes = 0; last_L = 0; last_R = 0; max_row = 0;

    env.sb.next_run(ok);
    while (ok) begin
      env.run_and_check();
      want = env.spec_cycles(env.sb.L, env.sb.R);
      env.sb.check32("BUSY cycles against the spec formula", env.busy_cnt, want);
      env.bfm.read(A_CYCLE, d);
      env.sb.check32("CYCLE_CNT against the spec formula", d, want);
      env.bfm.idle(7);
      env.bfm.read(A_CYCLE, d);
      env.sb.check32("CYCLE_CNT a few cycles after DONE", d, want);
      if (env.sb.L != last_L || env.sb.R != last_R) n_shapes++;
      last_L = env.sb.L;
      last_R = env.sb.R;
      if ((want - 1) / env.sb.R > max_row) max_row = (want - 1) / env.sb.R;
      env.sb.next_run(ok);
    end

    env.finish($sformatf("%0d runs over %0d (L, R) shapes, longest row %0d cycles",
                         env.n_runs_done, n_shapes, max_row));
  end

endmodule
