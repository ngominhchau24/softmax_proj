// tb_smx_dv_sanity.sv - DV test 1: sanity of smx_core through acc_* (simulation only).
//
// Purpose: prove the DV environment and the basic software sequence before the larger tests.
//   1. values after reset (design spec 3.4): STATUS, LEN, ROWS, SCALE_K, CYCLE_CNT read 0
//   2. HW_PARAM fields (requirements 5.2)
//   3. LEN, ROWS, SCALE_K write and read back
//   4. a few runs from model/vec_dv_sanity.py, Y compared bit-exact (REQ-VER-01, REQ-FUN-01)
// Run from sim/:  make testname=tb_smx_dv_sanity [P=8] [N_SEG=8]
`timescale 1ns/1ps

module tb_smx_dv_sanity;

  parameter int P     = 8;
  parameter int N_SEG = 8;

  import smx_dv_pkg::*;

  smx_dv_env #(.P(P), .N_SEG(N_SEG)) env ();

  task automatic test_reset_values();
    logic [31:0] d;
    env.sb.ctx = "reset_values";
    env.sb.check1("status_busy after reset", env.status_busy, 1'b0);
    env.sb.check1("status_done after reset", env.status_done, 1'b0);
    env.sb.check1("status_err after reset",  env.status_err,  1'b0);
    env.bfm.read(A_STATUS, d);   env.sb.check32("STATUS after reset",    d, 32'h0);
    env.bfm.read(A_LEN, d);      env.sb.check32("LEN after reset",       d, 32'h0);
    env.bfm.read(A_ROWS, d);     env.sb.check32("ROWS after reset",      d, 32'h0);
    env.bfm.read(A_SCALE_K, d);  env.sb.check32("SCALE_K after reset",   d, 32'h0);
    env.bfm.read(A_CYCLE, d);    env.sb.check32("CYCLE_CNT after reset", d, 32'h0);
    env.bfm.read(A_CTRL, d);     env.sb.check32("CTRL reads 0",          d, 32'h0);
  endtask

  task automatic test_hw_param();
    logic [31:0] d, want;
    env.sb.ctx = "hw_param";
    // [7:0] P, [11:8] log2 L_MAX, [19:12] R_MAX, [23:20] log2 N_SEG, [31:24] VERSION
    want = {HW_VERSION, 4'($clog2(N_SEG)), 8'(R_MAX), 4'($clog2(L_MAX)), 8'(P)};
    env.bfm.read(A_HWPARAM, d);
    env.sb.check32("HW_PARAM", d, want);
  endtask

  task automatic test_reg_readback();
    logic [31:0] d;
    env.sb.ctx = "reg_readback";
    env.bfm.write(A_LEN,     32'd197,   4'hF);
    env.bfm.write(A_ROWS,    32'd3,     4'hF);
    env.bfm.write(A_SCALE_K, 32'h1715,  4'hF);
    env.bfm.read(A_LEN, d);      env.sb.check32("LEN readback",     d, 32'd197);
    env.bfm.read(A_ROWS, d);     env.sb.check32("ROWS readback",    d, 32'd3);
    env.bfm.read(A_SCALE_K, d);  env.sb.check32("SCALE_K readback", d, 32'h1715);
    // writing the registers must not start anything
    env.sb.check1("status_busy without START", env.status_busy, 1'b0);
    env.sb.check1("status_done without START", env.status_done, 1'b0);
  endtask

  initial begin
    bit ok;
    env.init("tb_smx_dv_sanity", "dv.hex");

    test_reset_values();
    test_hw_param();
    test_reg_readback();

    env.sb.next_run(ok);
    while (ok) begin
      env.run_and_check();
      env.sb.next_run(ok);
    end

    env.finish($sformatf("%0d runs, %0d writes, %0d reads",
                         env.n_runs_done, env.bfm.n_wr, env.bfm.n_rd));
  end

endmodule
