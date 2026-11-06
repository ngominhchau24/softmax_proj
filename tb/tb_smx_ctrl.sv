// tb_smx_ctrl.sv - self-checking unit testbench for smx_ctrl (simulation only).
//
// The datapath is modelled behaviourally: the testbench delays grp_* by the pipeline
// latencies and feeds sum_last, div_done, y_valid, y_last back (event-driven loop).
// Independently, build_expected() computes from (L, R) the exact cycle of every
// output (05-cross-block.md section 5) and every cycle is compared against it.
// Latencies run in three configurations: smx_pkg, an extreme minimum, and a large one,
// to prove smx_ctrl has no hidden dependency on them.
// Block has no vectors; +VECDIR is accepted and ignored.
`timescale 1ns/1ps

module tb_smx_ctrl;

  parameter int P     = smx_pkg::P;
  parameter int N_SEG = smx_pkg::N_SEG;  // unused

  localparam int ADDR_W  = $clog2(8192 / P);
  localparam int GW      = ADDR_W - 4;
  localparam int NMAX    = 32768;
  localparam int MAX_MSG = 20;

  logic               clk = 1'b0;
  logic               rst_n;
  logic               start;
  logic [9:0]         len;
  logic [4:0]         rows;
  logic               grp_valid, grp_pass2, grp_first, grp_last;
  logic [P-1:0]       grp_en;
  logic [ADDR_W-1:0]  grp_addr;
  logic               sum_last, div_start, div_done, y_valid, y_last;
  logic [ADDR_W-1:0]  y_wr_addr;
  logic               run_done;

  always #5 clk = ~clk;

  smx_ctrl #(.P(P)) dut (.*);

  // ---- latency configuration (runtime) ----
  int lat_pipe, lat_sum, lat_norm, lat_div;

  // ---- expected trace, indexed by cycle of the case (cycle 0 = start cycle) ----
  logic               e_v   [NMAX];
  logic               e_p2  [NMAX];
  logic               e_f   [NMAX];
  logic               e_l   [NMAX];
  logic [P-1:0]       e_en  [NMAX];
  logic [ADDR_W-1:0]  e_ad  [NMAX];
  logic               e_ds  [NMAX];
  logic               e_yv  [NMAX];
  logic [ADDR_W-1:0]  e_ya  [NMAX];
  logic               e_rd  [NMAX];
  int                 e_hi;       // highest index written
  int                 e_rd_cyc;   // cycle of the expected run_done

  // ---- datapath event history: bit k = event k cycles ago (bit 0 = this cycle) ----
  logic [255:0] h_sl, h_yv, h_yl, h_ds;

  int    cyc, cur_l, cur_r;
  int    n_err, n_cases, n_cycles, n_groups, n_rows;
  int    rd_cnt, rd_cyc;
  string cfg_name;

  task automatic fail(input string what);
    n_err++;
    if (n_err <= MAX_MSG)
      $display("ERROR [%s L=%0d R=%0d cyc=%0d] %s", cfg_name, cur_l, cur_r, cyc, what);
  endtask

  task automatic clear_expected();
    for (int i = 0; i <= e_hi + 8 && i < NMAX; i++) begin
      e_v[i] = 1'b0; e_p2[i] = 1'b0; e_f[i] = 1'b0; e_l[i] = 1'b0; e_en[i] = '0;
      e_ad[i] = '0; e_ds[i] = 1'b0; e_yv[i] = 1'b0; e_ya[i] = '0; e_rd[i] = 1'b0;
    end
    e_hi = 0;
  endtask

  task automatic mark(input int t);
    if (t >= NMAX - 16) begin
      $display("TB internal error: trace index %0d too large", t);
      $finish;
    end
    if (t > e_hi) e_hi = t;
  endtask

  task automatic build_expected(input int l, input int r_cnt);
    int g_cnt, t0, t2, sl, ds, dd, yl, nr;
    clear_expected();
    g_cnt = (l + P - 1) / P;
    t0 = 1;                                  // start in cycle 0, first group one cycle later
    for (int r = 0; r < r_cnt; r++) begin
      for (int g = 0; g < g_cnt; g++) begin
        mark(t0 + g);
        e_v[t0+g]  = 1'b1;
        e_p2[t0+g] = 1'b0;
        e_f[t0+g]  = (g == 0);
        e_l[t0+g]  = (g == g_cnt - 1);
        for (int j = 0; j < P; j++) e_en[t0+g][j] = (g * P + j < l);
        e_ad[t0+g] = {r[3:0], g[GW-1:0]};
      end
      sl = t0 + g_cnt - 1 + lat_pipe + lat_sum;
      ds = sl + 1;
      mark(ds);
      e_ds[ds] = 1'b1;
      dd = ds + lat_div;
      t2 = dd + 1;
      for (int g = 0; g < g_cnt; g++) begin
        mark(t2 + g);
        e_v[t2+g]  = 1'b1;
        e_p2[t2+g] = 1'b1;
        e_f[t2+g]  = (g == 0);
        e_l[t2+g]  = (g == g_cnt - 1);
        for (int j = 0; j < P; j++) e_en[t2+g][j] = (g * P + j < l);
        e_ad[t2+g] = {r[3:0], g[GW-1:0]};
        mark(t2 + g + lat_pipe + lat_norm);
        e_yv[t2+g+lat_pipe+lat_norm] = 1'b1;
        e_ya[t2+g+lat_pipe+lat_norm] = {r[3:0], g[GW-1:0]};
      end
      yl = t2 + g_cnt - 1 + lat_pipe + lat_norm;
      nr = yl + 1;
      mark(nr);
      if (r == r_cnt - 1) begin
        e_rd[nr] = 1'b1;
        e_rd_cyc = nr;
      end
      t0 = nr + 1;
    end
  endtask

  // One clock cycle: advance to the middle of the next cycle, check outputs, push the
  // datapath model, drive the inputs of this cycle. Outputs depend on registers only,
  // so they are already final at the falling edge.
  task automatic step(input bit chk);
    logic exp_yv;
    @(negedge clk);
    cyc++;
    if (cyc == 0) begin
      len  = 10'(cur_l);
      rows = 5'(cur_r);
    end
    start = (cyc == 0);

    if (chk) begin
      n_cycles++;
      if (grp_valid !== e_v[cyc])         fail($sformatf("grp_valid %b exp %b", grp_valid, e_v[cyc]));
      else if (e_v[cyc]) begin
        n_groups++;
        if (grp_pass2 !== e_p2[cyc])      fail($sformatf("grp_pass2 %b exp %b", grp_pass2, e_p2[cyc]));
        if (grp_first !== e_f[cyc])       fail($sformatf("grp_first %b exp %b", grp_first, e_f[cyc]));
        if (grp_last  !== e_l[cyc])       fail($sformatf("grp_last %b exp %b", grp_last, e_l[cyc]));
        if (grp_en    !== e_en[cyc])      fail($sformatf("grp_en %h exp %h", grp_en, e_en[cyc]));
        if (grp_addr  !== e_ad[cyc])      fail($sformatf("grp_addr %h exp %h", grp_addr, e_ad[cyc]));
      end
      if (div_start !== e_ds[cyc])        fail($sformatf("div_start %b exp %b", div_start, e_ds[cyc]));
      if (run_done  !== e_rd[cyc])        fail($sformatf("run_done %b exp %b", run_done, e_rd[cyc]));
      if (run_done === 1'b1) begin rd_cnt++; rd_cyc = cyc; end
    end

    // datapath model
    h_sl = {h_sl[254:0], grp_valid & ~grp_pass2 & grp_last};
    h_yv = {h_yv[254:0], grp_valid &  grp_pass2};
    h_yl = {h_yl[254:0], grp_valid &  grp_pass2 & grp_last};
    h_ds = {h_ds[254:0], div_start};
    sum_last = h_sl[lat_pipe + lat_sum];
    y_valid  = h_yv[lat_pipe + lat_norm];
    y_last   = h_yl[lat_pipe + lat_norm];
    div_done = h_ds[lat_div];

    if (chk) begin
      exp_yv = e_yv[cyc];
      if (y_valid !== exp_yv) fail($sformatf("y_valid %b exp %b", y_valid, exp_yv));
      if (y_valid === 1'b1 && y_wr_addr !== e_ya[cyc])
        fail($sformatf("y_wr_addr %h exp %h", y_wr_addr, e_ya[cyc]));
    end
  endtask

  task automatic run_case(input int l, input int r_cnt, input int gap);
    int g_cnt, t_row;
    cur_l = l; cur_r = r_cnt;
    g_cnt = (l + P - 1) / P;
    build_expected(l, r_cnt);
    cyc = -1; rd_cnt = 0; rd_cyc = -1;
    for (int i = 0; i <= e_rd_cyc + gap; i++) step(1'b1);
    t_row = 2 * g_cnt + 2 * lat_pipe + lat_sum + lat_norm + lat_div + 2;
    if (rd_cnt != 1) fail($sformatf("run_done seen %0d times", rd_cnt));
    // busy cycles: start cycle (0) .. run_done cycle inclusive = R*T_row + 1
    if (rd_cyc + 1 != r_cnt * t_row + 1)
      fail($sformatf("busy cycles %0d exp %0d", rd_cyc + 1, r_cnt * t_row + 1));
    if (cfg_name == "pkg" && t_row != 2 * g_cnt + smx_pkg::ROW_OVERHEAD)
      fail("T_row differs from 2*G + smx_pkg::ROW_OVERHEAD");
    n_cases++;
    n_rows += r_cnt;
  endtask

  // Reset in the middle of a run at cycle 'cut' of the case, then idle checks.
  task automatic run_reset_case(input int l, input int r_cnt, input int cut);
    cur_l = l; cur_r = r_cnt;
    build_expected(l, r_cnt);
    cyc = -1; rd_cnt = 0;
    for (int i = 0; i < cut; i++) step(1'b1);
    @(negedge clk);
    cyc++;
    start = 1'b0;
    rst_n = 1'b0;
    #1;
    if (grp_valid !== 1'b0 || div_start !== 1'b0 || run_done !== 1'b0 || grp_en !== '0 ||
        grp_pass2 !== 1'b0 || grp_first !== 1'b0 || grp_last !== 1'b0)
      fail("outputs not idle right after reset assertion");
    sum_last = 1'b0; div_done = 1'b0; y_valid = 1'b0; y_last = 1'b0;
    h_sl = '0; h_yv = '0; h_yl = '0; h_ds = '0;
    for (int i = 0; i < 3; i++) begin
      @(negedge clk);
      if (grp_valid !== 1'b0 || div_start !== 1'b0 || run_done !== 1'b0)
        fail("outputs not idle during reset");
    end
    rst_n = 1'b1;
    for (int i = 0; i < 8; i++) begin
      @(negedge clk);
      if (grp_valid !== 1'b0 || div_start !== 1'b0 || run_done !== 1'b0)
        fail("outputs not idle after reset release without start");
    end
    n_cases++;
  endtask

  int ls [17];
  int rs [5];

  initial begin
    n_err = 0; n_cases = 0; n_cycles = 0; n_groups = 0; n_rows = 0; e_hi = 0;
    for (int i = 0; i < NMAX; i++) begin
      e_v[i] = 1'b0; e_p2[i] = 1'b0; e_f[i] = 1'b0; e_l[i] = 1'b0; e_en[i] = '0;
      e_ad[i] = '0; e_ds[i] = 1'b0; e_yv[i] = 1'b0; e_ya[i] = '0; e_rd[i] = 1'b0;
    end
    h_sl = '0; h_yv = '0; h_yl = '0; h_ds = '0;
    start = 1'b0; len = 10'd1; rows = 5'd1;
    sum_last = 1'b0; div_done = 1'b0; y_valid = 1'b0; y_last = 1'b0;
    cur_l = 0; cur_r = 0; cyc = -1; cfg_name = "init";
    rst_n = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    ls = '{1, 2, P-1, P, P+1, 2*P-1, 2*P, 2*P+1, 63, 64, 65, 127, 128, 129, 256, 511, 512};
    rs = '{1, 2, 3, 15, 16};

    for (int cfg = 0; cfg < 3; cfg++) begin
      case (cfg)
        0: begin cfg_name = "pkg"; lat_pipe = smx_pkg::PIPE_LAT; lat_sum = smx_pkg::SUMACC_LAT;
                 lat_norm = smx_pkg::NORM_LAT; lat_div = smx_pkg::DIV_LAT; end
        1: begin cfg_name = "min"; lat_pipe = 1; lat_sum = 0; lat_norm = 0; lat_div = 1; end
        default: begin cfg_name = "big"; lat_pipe = 20; lat_sum = 7; lat_norm = 9; lat_div = 45; end
      endcase
      // events of the previous configuration must not leak into this one
      h_sl = '0; h_yv = '0; h_yl = '0; h_ds = '0;
      // reference check of the formula against smx_pkg
      if (cfg == 0 && 2 * lat_pipe + lat_sum + lat_norm + lat_div + 2 != smx_pkg::ROW_OVERHEAD)
        fail("smx_pkg::ROW_OVERHEAD is not 2*PIPE_LAT + SUMACC_LAT + NORM_LAT + DIV_LAT + 2");

      for (int li = 0; li < 17; li++)
        for (int ri = 0; ri < 5; ri++)
          // back-to-back (gap 0), short and longer gaps; different (L, R) every run
          run_case(ls[li], rs[ri], (li + ri) % 3 == 0 ? 0 : ((li + ri) % 3 == 1 ? 1 : 5));
    end

    // reset in the middle of a run: one cut per phase (config "pkg"), then a full run
    cfg_name = "pkg";
    lat_pipe = smx_pkg::PIPE_LAT; lat_sum = smx_pkg::SUMACC_LAT;
    lat_norm = smx_pkg::NORM_LAT; lat_div = smx_pkg::DIV_LAT;
    begin
      int cuts [8];
      int g_cnt;
      g_cnt = (100 + P - 1) / P;
      cuts[0] = 2;                                                   // P1_RUN
      cuts[1] = 1 + g_cnt + 3;                                       // P1_DRAIN
      cuts[2] = 1 + g_cnt - 1 + lat_pipe + lat_sum + 1;              // DIV
      cuts[3] = 1 + g_cnt - 1 + lat_pipe + lat_sum + 1 + 10;         // DIV_WAIT
      cuts[4] = 1 + g_cnt - 1 + lat_pipe + lat_sum + 2 + lat_div + 2;// P2_RUN
      cuts[5] = 1 + 2*g_cnt - 1 + lat_pipe + lat_sum + 2 + lat_div + 4; // P2_DRAIN
      cuts[6] = 1 + 2*g_cnt - 1 + lat_pipe + lat_sum + 2 + lat_div + 1 + lat_pipe + lat_norm + g_cnt;
                                                                     // NEXT_ROW of row 0
      cuts[7] = 3 * (2*g_cnt + smx_pkg::ROW_OVERHEAD) / 2;           // somewhere in row 1
      for (int c = 0; c < 8; c++) begin
        run_reset_case(100, 4, cuts[c]);
        run_case(37 + c, 1 + (c % 3), 0);   // new run after reset, other L and R
      end
    end

    if (n_err == 0)
      $display("TB_RESULT: PASS  P=%0d  %0d cases (%0d rows, %0d groups, %0d cycles checked)",
               P, n_cases, n_rows, n_groups, n_cycles);
    else
      $display("TB_RESULT: FAIL  P=%0d  errors=%0d cases=%0d", P, n_err, n_cases);
    $finish;
  end

endmodule
