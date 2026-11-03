// tb_smx_norm.sv - self-checking unit testbench for smx_norm (simulation only).
//
// Reads t1..t4.hex made by model/vec_norm.py (via model/gen_vectors.py norm), drives
// one vector per cycle (Rcp changes per vector, aligned with E) and checks out_valid
// and y_out bit-exact, with exactly smx_pkg::NORM_LAT cycles of latency. Then checks
// reset in the middle of a stream. Prints "TB_RESULT: PASS" or "TB_RESULT: FAIL".
//
// Plusargs: +VECDIR=<dir> (default tb/vectors/smx_norm/p<P>_n<N_SEG>)
`timescale 1ns/1ps

module tb_smx_norm;

  parameter int P     = smx_pkg::P;      // unused: every testbench takes P and N_SEG
  parameter int N_SEG = smx_pkg::N_SEG;  // only selects the vector directory

  localparam int LAT     = smx_pkg::NORM_LAT;
  localparam int E_W     = smx_pkg::E_W;
  localparam int RCP_W   = smx_pkg::RCP_W;
  localparam int Y_W     = smx_pkg::Y_W;
  localparam int MAX_MSG = 20;

  logic             clk = 1'b0;
  logic             rst_n;
  logic             in_valid;
  logic [E_W-1:0]   e_in;
  logic [RCP_W-1:0] rcp_in;
  logic             out_valid;
  logic [Y_W-1:0]   y_out;

  always #5 clk = ~clk;  // 100 MHz

  smx_norm dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_valid  (in_valid),
    .e_in      (e_in),
    .rcp_in    (rcp_in),
    .out_valid (out_valid),
    .y_out     (y_out)
  );

  // hist_*[i] holds the vector driven i+1 cycles ago
  logic             hist_v [LAT];
  logic [Y_W-1:0]   hist_y [LAT];
  logic [E_W-1:0]   hist_e [LAT];
  logic [RCP_W-1:0] hist_r [LAT];
  int               hist_n [LAT];

  int    n_in, n_out, n_err;
  string vecdir;
  string cur_set;

  task automatic clear_hist();
    for (int i = 0; i < LAT; i++) begin
      hist_v[i] = 1'b0;
      hist_y[i] = '0;
      hist_e[i] = '0;
      hist_r[i] = '0;
      hist_n[i] = -1;
    end
  endtask

  task automatic report(input string what);
    n_err++;
    if (n_err <= MAX_MSG)
      $display("ERROR [%s] %s: vec#%0d e=%h rcp=%h exp_v=%0b exp_y=%h got_v=%b got_y=%h",
               cur_set, what, hist_n[LAT-1], hist_e[LAT-1], hist_r[LAT-1],
               hist_v[LAT-1], hist_y[LAT-1], out_valid, y_out);
  endtask

  // Called right after a falling edge: check the outputs against the vector
  // driven LAT cycles ago, drive the next vector, wait for the next falling edge.
  task automatic step(input logic v, input logic [E_W-1:0] e,
                      input logic [RCP_W-1:0] r, input logic [Y_W-1:0] y);
    if (out_valid !== hist_v[LAT-1])
      report("out_valid");
    else if (out_valid === 1'b1) begin
      n_out++;
      if (y_out !== hist_y[LAT-1])
        report("y_out");
    end

    for (int i = LAT-1; i > 0; i--) begin
      hist_v[i] = hist_v[i-1];
      hist_y[i] = hist_y[i-1];
      hist_e[i] = hist_e[i-1];
      hist_r[i] = hist_r[i-1];
      hist_n[i] = hist_n[i-1];
    end
    hist_v[0] = v;
    hist_y[0] = y;
    hist_e[0] = e;
    hist_r[0] = r;
    hist_n[0] = n_in;

    in_valid = v;
    e_in     = e;
    rcp_in   = r;
    if (v) n_in++;
    @(negedge clk);
  endtask

  task automatic drain();
    repeat (LAT + 1) step(1'b0, '0, '0, '0);
  endtask

  task automatic run_file(input string name);
    int          fd;
    int          cnt;
    string       line;
    logic [31:0] v, e, r, y;
    cur_set = name;
    cnt = 0;
    fd = $fopen({vecdir, "/", name, ".hex"}, "r");
    if (fd == 0) begin
      $display("ERROR: cannot open %s/%s.hex (run model/gen_vectors.py norm)", vecdir, name);
      n_err++;
      return;
    end
    while ($fgets(line, fd) != 0) begin
      if (line.len() < 2 || line[0] == "#") continue;
      if ($sscanf(line, "%h %h %h %h", v, e, r, y) != 4) begin
        $display("ERROR: bad line in %s.hex: %s", name, line);
        n_err++;
        continue;
      end
      step(v[0], e[E_W-1:0], r[RCP_W-1:0], y[Y_W-1:0]);
      cnt++;
    end
    $fclose(fd);
    drain();
    $display("[%s] %0d vectors, errors so far %0d", name, cnt, n_err);
  endtask

  // Reset while elements are in flight. Expected: E=32768, Rcp=2^16 -> y=1 (2^31+2^31
  // = 2^32 exactly); E=65535, Rcp=2^27-1 -> 255 (saturated); E=0 -> 0.
  task automatic reset_test();
    int lost;
    cur_set = "reset";
    step(1'b1, 16'd32768, 27'd65536, 8'd1);
    step(1'b1, 16'd65535, 27'h7ffffff, 8'd255);
    step(1'b1, 16'd32768, 27'd65536, 8'd1);
    // assert reset with three elements still in the pipeline
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
    step(1'b1, 16'd32768, 27'd65536, 8'd1);
    step(1'b1, 16'd65535, 27'h7ffffff, 8'd255);
    step(1'b1, 16'd0,     27'h7ffffff, 8'd0);
    step(1'b0, 16'd1,     27'd1,       8'd0);
    step(1'b1, 16'd1,     27'd1,       8'd0);
    drain();
    $display("[reset] reset mid-stream, errors so far %0d", n_err);
  endtask

  initial begin
    if (!$value$plusargs("VECDIR=%s", vecdir))
      vecdir = $sformatf("tb/vectors/smx_norm/p%0d_n%0d", P, N_SEG);
    $display("tb_smx_norm: NORM_LAT=%0d VECDIR=%s", LAT, vecdir);

    n_in  = 0;
    n_out = 0;
    n_err = 0;
    cur_set = "init";
    clear_hist();
    rst_n    = 1'b0;
    in_valid = 1'b0;
    e_in     = '0;
    rcp_in   = '0;
    repeat (3) @(negedge clk);
    if (out_valid !== 1'b0) report("out_valid during initial reset");
    rst_n = 1'b1;

    run_file("t1");
    run_file("t3");
    run_file("t2");
    run_file("t4");
    reset_test();

    if (n_err == 0 && n_in == n_out)
      $display("TB_RESULT: PASS  P=%0d N_SEG=%0d  %0d elements checked", P, N_SEG, n_out);
    else
      $display("TB_RESULT: FAIL  P=%0d N_SEG=%0d  errors=%0d  in=%0d out=%0d",
               P, N_SEG, n_err, n_in, n_out);
    $finish;
  end

endmodule
