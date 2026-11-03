// tb_smx_divider.sv - self-checking unit testbench for smx_divider (simulation only).
//
// Reads t1.hex (edges) and t2.hex (random) made by model/gen_vectors.py divider, one run per
// line "sum rcp". Every cycle the checker compares done and rcp_out against a scoreboard:
//   - done is high exactly smx_pkg::DIV_LAT cycles after each start and never otherwise
//   - at done, rcp_out equals the golden value; between dones it holds the last result
// "Cycle s" is the cycle in which start is driven (at a falling edge, sampled by the next rising
// edge); outputs are checked at the falling edge, so done must be seen at cycle s + DIV_LAT.
// Run spacing is varied: start in the same cycle as done, right after done, and later.
// sum_in is driven with garbage (random, all-ones, X) in every cycle except the start cycle.
// Then reset during a division at several offsets (T-reset). Prints TB_RESULT: PASS or FAIL.
//
// Plusargs: +VECDIR=<dir> (default tb/vectors/smx_divider/p<P>_n<N_SEG>)
`timescale 1ns/1ps

module tb_smx_divider;

  parameter int P     = smx_pkg::P;      // unused, every testbench takes P and N_SEG
  parameter int N_SEG = smx_pkg::N_SEG;  // unused

  localparam int LAT     = smx_pkg::DIV_LAT;
  localparam int SUM_W   = smx_pkg::SUM_W;
  localparam int RCP_W   = smx_pkg::RCP_W;
  localparam int MAX_MSG = 20;

  logic              clk = 1'b0;
  logic              rst_n;
  logic              start;
  logic [SUM_W-1:0]  sum_in;
  logic              done;
  logic [RCP_W-1:0]  rcp_out;

  always #5 clk = ~clk;  // 100 MHz

  smx_divider dut (
    .clk     (clk),
    .rst_n   (rst_n),
    .start   (start),
    .sum_in  (sum_in),
    .done    (done),
    .rcp_out (rcp_out)
  );

  // scoreboard: expected done cycle and value of every run in flight
  int              cyc;
  int              exp_cyc [$];
  logic [RCP_W-1:0] exp_rcp [$];
  logic [SUM_W-1:0] exp_sum [$];
  logic [RCP_W-1:0] cur_rcp;
  bit              known;
  int              n_run, n_done, n_hold, n_err;
  string           vecdir, cur_set;
  int              nxt_start;   // earliest cycle for the next start
  // reset offsets relative to the start cycle: early, mid, last iteration edge, done cycle, after
  int              OFFS [6] = '{1, 5, 14, 27, 28, 29};

  task automatic report(input string what);
    n_err++;
    if (n_err <= MAX_MSG)
      $display("ERROR [%s] cyc=%0d %s: done=%b rcp_out=%h (exp_rcp=%h sum=%h)", cur_set, cyc, what,
               done, rcp_out, (exp_rcp.size() > 0) ? exp_rcp[0] : cur_rcp,
               (exp_sum.size() > 0) ? exp_sum[0] : 25'h0);
  endtask

  // Called right after a falling edge: check outputs of this cycle, drive inputs of this cycle,
  // wait for the next falling edge.
  task automatic step(input logic st, input logic [SUM_W-1:0] s, input logic [RCP_W-1:0] r);
    logic exp_done;
    exp_done = (exp_cyc.size() > 0) && (exp_cyc[0] == cyc);
    if (done !== exp_done) report(exp_done ? "done missing" : "done unexpected");
    else if (exp_done) begin
      if (rcp_out !== exp_rcp[0]) report("rcp_out at done");
      cur_rcp = exp_rcp[0];
      known   = 1'b1;
      n_done++;
      void'(exp_cyc.pop_front());
      void'(exp_rcp.pop_front());
      void'(exp_sum.pop_front());
    end else if (known) begin
      n_hold++;
      if (rcp_out !== cur_rcp) report("rcp_out not held");
    end

    start = st;
    if (st) begin
      sum_in = s;
      exp_cyc.push_back(cyc + LAT);
      exp_rcp.push_back(r);
      exp_sum.push_back(s);
      n_run++;
    end else begin
      case ($urandom_range(0, 7))
        0:       sum_in = 'x;
        1:       sum_in = '1;
        2:       sum_in = '0;
        default: sum_in = $urandom();
      endcase
    end
    @(negedge clk);
    cyc++;
  endtask

  task automatic idle();
    step(1'b0, '0, '0);
  endtask

  // One run, started at the earliest allowed cycle plus gap idle cycles.
  task automatic run1(input logic [SUM_W-1:0] s, input logic [RCP_W-1:0] r, input int gap);
    while (cyc < nxt_start + gap) idle();
    step(1'b1, s, r);
    nxt_start = cyc - 1 + LAT;   // start in the very cycle done is high
  endtask

  task automatic drain();
    while (exp_cyc.size() > 0 || cyc < nxt_start + 2) idle();
    repeat (3) idle();
  endtask

  task automatic run_file(input string name);
    int          fd, cnt, gap;
    string       line;
    logic [31:0] s, r;
    cur_set = name;
    cnt = 0;
    fd = $fopen({vecdir, "/", name, ".hex"}, "r");
    if (fd == 0) begin
      $display("ERROR: cannot open %s/%s.hex (run model/gen_vectors.py divider)", vecdir, name);
      n_err++;
      return;
    end
    while ($fgets(line, fd) != 0) begin
      if (line.len() < 2 || line[0] == "#") continue;
      if ($sscanf(line, "%h %h", s, r) != 2) begin
        $display("ERROR: bad line in %s.hex: %s", name, line);
        n_err++;
        continue;
      end
      // gap 0: start in the done cycle; 1: right after done; else a few idle cycles
      case (cnt % 4)
        0:       gap = 0;
        1:       gap = 1;
        default: gap = $urandom_range(0, 4);
      endcase
      run1(s[SUM_W-1:0], r[RCP_W-1:0], gap);
      cnt++;
    end
    $fclose(fd);
    drain();
    $display("[%s] %0d runs, errors so far %0d", name, cnt, n_err);
  endtask

  // Reset (asynchronous, mid-cycle) at the start of cycle s + off of a run. Afterwards done must
  // stay low, rcp_out is not checked (reset does not clear it), and a new start must work.
  task automatic reset_test(input int off);
    int s0;
    cur_set = $sformatf("reset+%0d", off);
    drain();
    s0 = cyc;
    step(1'b1, 25'h100000, 27'h100000);
    while (cyc < s0 + off) idle();
    rst_n = 1'b0;
    #1;
    if (done !== 1'b0) report("done not cleared by async reset");
    n_run -= exp_cyc.size();   // flushed by reset, never come out
    exp_cyc.delete();
    exp_rcp.delete();
    exp_sum.delete();
    known = 1'b0;
    repeat (3) idle();
    rst_n = 1'b1;
    // quiet for a full division time: done must stay low
    repeat (LAT + 4) idle();
    nxt_start = cyc;
    run1(25'h4000, 27'h4000000, 0);
    run1(25'hffffff, 27'h10000, 0);
    drain();
    $display("[reset+%0d] errors so far %0d", off, n_err);
  endtask

  initial begin
    if (!$value$plusargs("VECDIR=%s", vecdir))
      vecdir = $sformatf("tb/vectors/smx_divider/p%0d_n%0d", P, N_SEG);
    $display("tb_smx_divider: DIV_LAT=%0d VECDIR=%s", LAT, vecdir);

    n_run = 0; n_done = 0; n_hold = 0; n_err = 0;
    cyc = 0; nxt_start = 0; known = 1'b0; cur_rcp = '0;
    cur_set = "init";
    rst_n  = 1'b0;
    start  = 1'b0;
    sum_in = '0;
    #1;
    if (done !== 1'b0) report("done during initial reset");
    repeat (3) @(negedge clk);
    cyc = 0;
    rst_n = 1'b1;
    nxt_start = 0;

    run_file("t1");
    run_file("t2");
    for (int i = 0; i < 6; i++) reset_test(OFFS[i]);

    if (n_err == 0 && n_run == n_done && n_run > 0)
      $display("TB_RESULT: PASS  %0d divisions checked, %0d hold cycles", n_done, n_hold);
    else
      $display("TB_RESULT: FAIL  errors=%0d runs=%0d done=%0d", n_err, n_run, n_done);
    $finish;
  end

endmodule
