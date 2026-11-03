// tb_smx_sumacc.sv - self-checking unit testbench for smx_sumacc (simulation only).
//
// Reads t1..t5.hex made by model/vec_sumacc.py (via model/gen_vectors.py), drives one
// line per cycle and checks out_valid and sum_out bit-exact, with exactly
// smx_pkg::SUMACC_LAT cycles of latency. sum_out is checked on every cycle after the
// first valid group, so "hold when no new group arrives" is covered. t5 is driven
// twice with an async reset in flight in between.
// Prints "TB_RESULT: PASS" or "TB_RESULT: FAIL".
//
// Plusargs: +VECDIR=<dir> (default tb/vectors/smx_sumacc/p<P>_n<N_SEG>)
`timescale 1ns/1ps

module tb_smx_sumacc;

  parameter int P     = smx_pkg::P;
  parameter int N_SEG = smx_pkg::N_SEG;  // used by the vector generator only

  localparam int LAT     = smx_pkg::SUMACC_LAT;
  localparam int E_W     = smx_pkg::E_W;
  localparam int DM_W    = smx_pkg::DM_W;
  localparam int SUM_W   = smx_pkg::SUM_W;
  localparam int MAX_MSG = 20;

  logic                      clk = 1'b0;
  logic                      rst_n;
  logic                      in_valid;
  logic                      in_first;
  logic [P-1:0][E_W-1:0]     e_in;
  logic [DM_W-1:0]           dm_in;
  logic                      out_valid;
  logic [SUM_W-1:0]          sum_out;

  always #5 clk = ~clk;  // 100 MHz

  smx_sumacc #(.P(P)) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_valid  (in_valid),
    .in_first  (in_first),
    .e_in      (e_in),
    .dm_in     (dm_in),
    .out_valid (out_valid),
    .sum_out   (sum_out)
  );

  // hist_*[i] holds the line driven i+1 cycles ago
  logic            hist_v   [LAT];
  logic [SUM_W-1:0] hist_s  [LAT];
  logic            hist_f   [LAT];
  logic [DM_W-1:0] hist_dm  [LAT];
  int              hist_n   [LAT];

  int    n_in, n_out, n_err;
  logic [SUM_W-1:0] last_s;  // expected sum after the latest driven line
  bit    seen;            // a valid group has left the pipe since the last reset / set start
  string vecdir;
  string cur_set;

  task automatic clear_hist();
    for (int i = 0; i < LAT; i++) begin
      hist_v[i]  = 1'b0;
      hist_s[i]  = '0;
      hist_f[i]  = 1'b0;
      hist_dm[i] = '0;
      hist_n[i]  = -1;
    end
  endtask

  task automatic report(input string what);
    n_err++;
    if (n_err <= MAX_MSG)
      $display("ERROR [%s] %s: line#%0d first=%0b dm=%0d exp_v=%0b exp_sum=%h got_v=%b got_sum=%h",
               cur_set, what, hist_n[LAT-1], hist_f[LAT-1], hist_dm[LAT-1],
               hist_v[LAT-1], hist_s[LAT-1], out_valid, sum_out);
  endtask

  // Called right after a falling edge: check the outputs against the line driven
  // LAT cycles ago, drive the next line, wait for the next falling edge.
  task automatic step(input logic v, input logic f, input logic [DM_W-1:0] dm,
                      input logic [P*E_W-1:0] e, input logic [SUM_W-1:0] s);
    if (out_valid !== hist_v[LAT-1])
      report("out_valid");
    else if (out_valid === 1'b1) begin
      n_out++;
      seen = 1'b1;
    end
    if (seen && sum_out !== hist_s[LAT-1])
      report("sum_out");

    for (int i = LAT-1; i > 0; i--) begin
      hist_v[i]  = hist_v[i-1];
      hist_s[i]  = hist_s[i-1];
      hist_f[i]  = hist_f[i-1];
      hist_dm[i] = hist_dm[i-1];
      hist_n[i]  = hist_n[i-1];
    end
    hist_v[0]  = v;
    hist_s[0]  = s;
    hist_f[0]  = f;
    hist_dm[0] = dm;
    hist_n[0]  = n_in;
    if (v) last_s = s;

    in_valid = v;
    in_first = f;
    dm_in    = dm;
    e_in     = e;
    if (v) n_in++;
    @(negedge clk);
  endtask

  task automatic drain();
    repeat (LAT + 1) step(1'b0, 1'b0, '0, '0, last_s);
  endtask

  // Drive file `name`; if stop_after >= 0, stop after that many lines (no drain).
  task automatic run_file(input string name, input int stop_after);
    int                fd;
    int                cnt;
    string             line;
    logic [31:0]       v, f, dm, s;
    logic [P*E_W-1:0]  e;
    cur_set = name;
    cnt = 0;
    seen = 1'b0;
    fd = $fopen({vecdir, "/", name, ".hex"}, "r");
    if (fd == 0) begin
      $display("ERROR: cannot open %s/%s.hex (run model/gen_vectors.py sumacc --p %0d --n-seg %0d)",
               vecdir, name, P, N_SEG);
      n_err++;
      return;
    end
    while ($fgets(line, fd) != 0) begin
      if (line.len() < 2 || line[0] == "#") continue;
      if ($sscanf(line, "%h %h %h %h %h", v, f, dm, e, s) != 5) begin
        $display("ERROR: bad line in %s.hex: %s", name, line);
        n_err++;
        continue;
      end
      step(v[0], f[0], dm[DM_W-1:0], e, s[SUM_W-1:0]);
      cnt++;
      if (stop_after >= 0 && cnt == stop_after) begin
        $fclose(fd);
        return;
      end
    end
    $fclose(fd);
    drain();
    $display("[%s] %0d lines, errors so far %0d", name, cnt, n_err);
  endtask

  // T5: reset while groups are in flight, then a full row from the start.
  task automatic reset_test();
    int lost;
    run_file("t5", LAT + 2);   // stops with LAT+2 lines driven, LAT in flight
    rst_n = 1'b0;
    #1;
    if (out_valid !== 1'b0) report("out_valid not cleared by async reset");
    lost = 0;
    for (int i = 0; i < LAT; i++) if (hist_v[i]) lost++;
    n_in -= lost;  // flushed by reset, never come out
    clear_hist();
    in_valid = 1'b0;
    repeat (2) begin
      @(negedge clk);
      if (out_valid !== 1'b0) report("out_valid during reset");
    end
    rst_n = 1'b1;
    run_file("t5", -1);
    $display("[t5] reset mid-stream, errors so far %0d", n_err);
  endtask

  initial begin
    if (!$value$plusargs("VECDIR=%s", vecdir))
      vecdir = $sformatf("tb/vectors/smx_sumacc/p%0d_n%0d", P, N_SEG);
    $display("tb_smx_sumacc: P=%0d SUMACC_LAT=%0d VECDIR=%s", P, LAT, vecdir);

    n_in  = 0;
    n_out = 0;
    n_err = 0;
    seen  = 1'b0;
    last_s = '0;
    cur_set = "init";
    clear_hist();
    rst_n    = 1'b0;
    in_valid = 1'b0;
    in_first = 1'b0;
    e_in     = '0;
    dm_in    = '0;
    repeat (3) @(negedge clk);
    if (out_valid !== 1'b0) report("out_valid during initial reset");
    rst_n = 1'b1;

    run_file("t1", -1);
    run_file("t2", -1);
    run_file("t3", -1);
    run_file("t4", -1);
    reset_test();

    if (n_err == 0 && n_in == n_out)
      $display("TB_RESULT: PASS  P=%0d  %0d groups checked", P, n_out);
    else
      $display("TB_RESULT: FAIL  P=%0d  errors=%0d  in=%0d out=%0d", P, n_err, n_in, n_out);
    $finish;
  end

endmodule
