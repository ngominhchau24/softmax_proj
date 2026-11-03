// tb_smx_maxtree.sv - self-checking unit testbench for smx_maxtree (simulation only).
//
// Reads t1.hex made by model/vec_maxtree.py (via gen_vectors.py), one clock cycle per line,
// and checks, exactly smx_pkg::MAXTREE_LAT cycles after each line:
//   out_valid                  equals the valid driven then
//   m_out                      every cycle once defined: Mnew after a valid group, held otherwise
//                              (cycles with in_valid = 0 carry random in_first, in_en, c_in, and
//                              X in masked lanes: M must not move and must never be X)
//   dm_out                     on valid groups, never X
// Then: all-X c_in with in_first = 1 and in_valid = 0 (M must hold), and reset in mid-stream.
// Prints one "TB_RESULT: PASS" or "TB_RESULT: FAIL" line.
//
// Plusargs: +VECDIR=<dir> (default tb/vectors/smx_maxtree/p<P>_n<N_SEG>)
`timescale 1ns/1ps

module tb_smx_maxtree;

  parameter int P     = smx_pkg::P;
  parameter int N_SEG = smx_pkg::N_SEG;  // unused, every testbench takes P and N_SEG

  localparam int LAT     = smx_pkg::MAXTREE_LAT;
  localparam int C_W     = smx_pkg::C_W;
  localparam int DM_W    = smx_pkg::DM_W;
  localparam int MAX_MSG = 20;

  logic                     clk = 1'b0;
  logic                     rst_n;
  logic                     in_valid;
  logic                     in_first;
  logic [P-1:0]             in_en;
  logic [P-1:0][C_W-1:0]    c_in;
  logic                     out_valid;
  logic [C_W-1:0]           m_out;
  logic [DM_W-1:0]          dm_out;

  always #5 clk = ~clk;  // 100 MHz

  smx_maxtree #(.P(P)) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_valid  (in_valid),
    .in_first  (in_first),
    .in_en     (in_en),
    .c_in      (c_in),
    .out_valid (out_valid),
    .m_out     (m_out),
    .dm_out    (dm_out)
  );

  // hist_*[i] holds the line driven i+1 cycles ago
  logic            hist_v [LAT];
  logic [C_W-1:0]  hist_m [LAT];
  logic [DM_W-1:0] hist_d [LAT];
  logic            hist_mk[LAT];
  logic            hist_dk[LAT];
  int              hist_n [LAT];

  int    n_in, n_out, n_hold, n_err, n_line;
  string vecdir;
  string cur_set;

  task automatic clear_hist();
    for (int i = 0; i < LAT; i++) begin
      hist_v[i]  = 1'b0;
      hist_m[i]  = '0;
      hist_d[i]  = '0;
      hist_mk[i] = 1'b0;
      hist_dk[i] = 1'b0;
      hist_n[i]  = -1;
    end
  endtask

  task automatic report(input string what);
    n_err++;
    if (n_err <= MAX_MSG)
      $display("ERROR [%s] %s: line#%0d exp_v=%0b exp_m=%0d(mk=%0b) exp_dm=%0d(dk=%0b) got_v=%b got_m=%0d got_dm=%0d",
               cur_set, what, hist_n[LAT-1], hist_v[LAT-1], $signed(hist_m[LAT-1]), hist_mk[LAT-1],
               hist_d[LAT-1], hist_dk[LAT-1], out_valid, $signed(m_out), dm_out);
  endtask

  // Called right after a falling edge: check the outputs against the line driven LAT cycles
  // ago, drive the next line, wait for the next falling edge. xm: 0 garbage in masked lanes,
  // 1 X in masked lanes, 2 X in odd masked lanes, 3 X in every lane (legal only with v = 0).
  task automatic step(input logic v, input logic f, input logic [P-1:0] en,
                      input logic [P*C_W-1:0] cv, input logic [C_W-1:0] m,
                      input logic [DM_W-1:0] d, input logic mk, input logic dk,
                      input int xm);
    // ---- check ----
    if (out_valid !== hist_v[LAT-1])
      report("out_valid");
    else if (hist_v[LAT-1] === 1'b1)
      n_out++;
    if (hist_mk[LAT-1]) begin
      n_hold++;
      if (m_out !== hist_m[LAT-1])
        report("m_out");
    end
    if (hist_dk[LAT-1] && dm_out !== hist_d[LAT-1])
      report("dm_out");

    // ---- shift history, then drive ----
    for (int i = LAT-1; i > 0; i--) begin
      hist_v[i]  = hist_v[i-1];
      hist_m[i]  = hist_m[i-1];
      hist_d[i]  = hist_d[i-1];
      hist_mk[i] = hist_mk[i-1];
      hist_dk[i] = hist_dk[i-1];
      hist_n[i]  = hist_n[i-1];
    end
    hist_v[0]  = v;
    hist_m[0]  = m;
    hist_d[0]  = d;
    hist_mk[0] = mk;
    hist_dk[0] = dk;
    hist_n[0]  = n_line;

    in_valid = v;
    in_first = f;
    in_en    = en;
    for (int j = 0; j < P; j++) begin
      if (xm == 3 || (!en[j] && (xm == 1 || (xm == 2 && (j % 2) == 1))))
        c_in[j] = 'x;
      else
        c_in[j] = cv[j*C_W +: C_W];
    end
    if (v) n_in++;
    n_line++;
    @(negedge clk);
  endtask

  task automatic drain();
    repeat (LAT + 1) step(1'b0, 1'b0, '0, '0, '0, '0, 1'b0, 1'b0, 0);
  endtask

  task automatic run_file(input string name);
    int                fd;
    int                cnt;
    string             line;
    logic [31:0]       v, f, mk, dk, xm;
    logic [P-1:0]      en;
    logic [P*C_W-1:0]  cv;
    logic [31:0]       m, d;
    cur_set = name;
    cnt = 0;
    fd = $fopen({vecdir, "/", name, ".hex"}, "r");
    if (fd == 0) begin
      $display("ERROR: cannot open %s/%s.hex (run model/gen_vectors.py maxtree --p %0d)",
               vecdir, name, P);
      n_err++;
      return;
    end
    while ($fgets(line, fd) != 0) begin
      if (line.len() < 2 || line[0] == "#") continue;
      if ($sscanf(line, "%h %h %h %h %h %h %h %h %h", v, f, en, cv, m, d, mk, dk, xm) != 9) begin
        $display("ERROR: bad line in %s.hex: %s", name, line);
        n_err++;
        continue;
      end
      step(v[0], f[0], en, cv, m[C_W-1:0], d[DM_W-1:0], mk[0], dk[0], int'(xm));
      cnt++;
    end
    $fclose(fd);
    $display("[%s] %0d cycles, errors so far %0d", name, cnt, n_err);
  endtask

  // Helper for the directed tests: a group with lane 0 = c0 and all other lanes = c1, all enabled
  function automatic logic [P*C_W-1:0] mk_c(input int c0, input int c1);
    logic [P*C_W-1:0] r;
    for (int j = 0; j < P; j++) r[j*C_W +: C_W] = (j == 0) ? C_W'(c0) : C_W'(c1);
    return r;
  endfunction

  // M must hold while in_valid = 0, even with in_first = 1 and all-X c_in and in_en.
  task automatic hold_test();
    cur_set = "hold";
    step(1'b1, 1'b1, '1, mk_c(17, -50), 9'(17), 8'd0, 1'b1, 1'b1, 0);   // M = 17
    repeat (6) step(1'b0, 1'b1, '1, '0, 9'(17), 8'd0, 1'b1, 1'b0, 3);  // first = 1 but no valid
    step(1'b1, 1'b0, '1, mk_c(40, 0), 9'(40), 8'd23, 1'b1, 1'b1, 0);
    repeat (6) step(1'b0, 1'b1, '0, '0, 9'(40), 8'd0, 1'b1, 1'b0, 3);
    step(1'b1, 1'b0, '1, mk_c(-100, 39), 9'(40), 8'd0, 1'b1, 1'b1, 0); // 39 < 40: M and dM stay
    drain();
    $display("[hold] errors so far %0d", n_err);
  endtask

  // Reset while a group is in flight: out_valid drops at once; the next row starts clean.
  task automatic reset_test();
    int lost;
    cur_set = "reset";
    step(1'b1, 1'b1, '1, mk_c(100, 0), 9'(100), 8'd0, 1'b1, 1'b1, 0);
    step(1'b1, 1'b0, '1, mk_c(120, 0), 9'(120), 8'd20, 1'b1, 1'b1, 0);
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
    step(1'b1, 1'b1, '1, mk_c(-7, -90), -9'sd7, 8'd0, 1'b1, 1'b1, 0);   // first: M = -7, not 120
    step(1'b1, 1'b0, '1, mk_c(6, -90), 9'(6), 8'd13, 1'b1, 1'b1, 0);
    drain();
    $display("[reset] reset mid-stream, errors so far %0d", n_err);
  endtask

  initial begin
    if (!$value$plusargs("VECDIR=%s", vecdir))
      vecdir = $sformatf("tb/vectors/smx_maxtree/p%0d_n%0d", P, N_SEG);
    $display("tb_smx_maxtree: P=%0d MAXTREE_LAT=%0d VECDIR=%s", P, LAT, vecdir);

    n_in = 0; n_out = 0; n_hold = 0; n_err = 0; n_line = 0;
    cur_set = "init";
    clear_hist();
    rst_n    = 1'b0;
    in_valid = 1'b0;
    in_first = 1'b0;
    in_en    = '0;
    c_in     = '0;
    repeat (3) @(negedge clk);
    if (out_valid !== 1'b0) report("out_valid during initial reset");
    rst_n = 1'b1;

    run_file("t1");
    drain();
    hold_test();
    reset_test();

    if (n_err == 0 && n_in == n_out)
      $display("TB_RESULT: PASS  P=%0d  %0d groups checked, %0d m_out samples (hold included)", P, n_out, n_hold);
    else
      $display("TB_RESULT: FAIL  P=%0d  errors=%0d in=%0d out=%0d", P, n_err, n_in, n_out);
    $finish;
  end

endmodule
