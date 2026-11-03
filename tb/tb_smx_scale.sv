// tb_smx_scale.sv - self-checking unit testbench for smx_scale (simulation only).
//
// Reads t1..t3.hex made by model/gen_vectors.py scale, drives one vector per cycle
// and checks out_valid, u_out and c_out bit-exact, with exactly smx_pkg::SCALE_LAT
// cycles of latency. Then checks reset in the middle of a stream (T4).
// Prints "TB_RESULT: PASS" or "TB_RESULT: FAIL".
//
// Plusargs: +VECDIR=<dir> (default tb/vectors/smx_scale/p<P>_n<N_SEG>)
`timescale 1ns/1ps

module tb_smx_scale;

  parameter int P     = smx_pkg::P;      // unused, every testbench takes P and N_SEG
  parameter int N_SEG = smx_pkg::N_SEG;  // unused

  localparam int LAT     = smx_pkg::SCALE_LAT;
  localparam int Q_W     = smx_pkg::Q_W;
  localparam int K_W     = smx_pkg::K_W;
  localparam int U_W     = smx_pkg::U_W;
  localparam int C_W     = smx_pkg::C_W;
  localparam int MAX_MSG = 20;

  logic                  clk = 1'b0;
  logic                  rst_n;
  logic                  in_valid;
  logic signed [Q_W-1:0] q_in;
  logic        [K_W-1:0] k_in;
  logic                  out_valid;
  logic signed [U_W-1:0] u_out;
  logic signed [C_W-1:0] c_out;

  always #5 clk = ~clk;  // 100 MHz

  smx_scale dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_valid  (in_valid),
    .q_in      (q_in),
    .k_in      (k_in),
    .out_valid (out_valid),
    .u_out     (u_out),
    .c_out     (c_out)
  );

  // hist_*[i] holds the vector driven i+1 cycles ago
  logic           hist_v [LAT];
  logic [Q_W-1:0] hist_q [LAT];
  logic [K_W-1:0] hist_k [LAT];
  logic [U_W-1:0] hist_u [LAT];
  logic [C_W-1:0] hist_c [LAT];
  int             hist_n [LAT];

  int    n_in, n_out, n_err;
  string vecdir;
  string cur_set;

  task automatic clear_hist();
    for (int i = 0; i < LAT; i++) begin
      hist_v[i] = 1'b0;
      hist_q[i] = '0;
      hist_k[i] = '0;
      hist_u[i] = '0;
      hist_c[i] = '0;
      hist_n[i] = -1;
    end
  endtask

  task automatic report(input string what);
    n_err++;
    if (n_err <= MAX_MSG)
      $display("ERROR [%s] %s: vec#%0d q=%h k=%h exp_v=%0b exp_u=%h exp_c=%h got_v=%b got_u=%h got_c=%h",
               cur_set, what, hist_n[LAT-1], hist_q[LAT-1], hist_k[LAT-1], hist_v[LAT-1],
               hist_u[LAT-1], hist_c[LAT-1], out_valid, u_out, c_out);
  endtask

  // Called right after a falling edge: check the outputs against the vector
  // driven LAT cycles ago, drive the next vector, wait for the next falling edge.
  task automatic step(input logic v, input logic [Q_W-1:0] q, input logic [K_W-1:0] k,
                      input logic [U_W-1:0] u, input logic [C_W-1:0] c);
    if (out_valid !== hist_v[LAT-1])
      report("out_valid");
    else if (out_valid === 1'b1) begin
      n_out++;
      if (u_out !== hist_u[LAT-1])
        report("u_out");
      else if (c_out !== hist_c[LAT-1])
        report("c_out");
    end

    for (int i = LAT-1; i > 0; i--) begin
      hist_v[i] = hist_v[i-1];
      hist_q[i] = hist_q[i-1];
      hist_k[i] = hist_k[i-1];
      hist_u[i] = hist_u[i-1];
      hist_c[i] = hist_c[i-1];
      hist_n[i] = hist_n[i-1];
    end
    hist_v[0] = v;
    hist_q[0] = q;
    hist_k[0] = k;
    hist_u[0] = u;
    hist_c[0] = c;
    hist_n[0] = n_in;

    in_valid = v;
    q_in     = q;
    k_in     = k;
    if (v) n_in++;
    @(negedge clk);
  endtask

  task automatic drain();
    repeat (LAT + 1) step(1'b0, '0, '0, '0, '0);
  endtask

  task automatic run_file(input string name);
    int          fd;
    int          cnt;
    string       line;
    logic [31:0] v, q, k, u, c;
    cur_set = name;
    cnt = 0;
    fd = $fopen({vecdir, "/", name, ".hex"}, "r");
    if (fd == 0) begin
      $display("ERROR: cannot open %s/%s.hex (run model/gen_vectors.py scale)", vecdir, name);
      n_err++;
      return;
    end
    while ($fgets(line, fd) != 0) begin
      if (line.len() < 2 || line[0] == "#") continue;
      if ($sscanf(line, "%h %h %h %h %h", v, q, k, u, c) != 5) begin
        $display("ERROR: bad line in %s.hex: %s", name, line);
        n_err++;
        continue;
      end
      step(v[0], q[Q_W-1:0], k[K_W-1:0], u[U_W-1:0], c[C_W-1:0]);
      cnt++;
    end
    $fclose(fd);
    drain();
    $display("[%s] %0d vectors, errors so far %0d", name, cnt, n_err);
  endtask

  // T4: reset while elements are in flight, then a fresh stream must be right.
  // Hand-written expectations: -3 * 40000 = -120000 -> c = -1 (ceil(-1.83));
  // -1 * 65536... K is 16 bit, so use 127 * 65535 = 8322945 -> c = 127.
  task automatic reset_test();
    int lost;
    cur_set = "t4";
    step(1'b1, 8'hFD, 16'd40000, 25'(-120000), 9'(-1));
    step(1'b1, 8'd127, 16'hFFFF, 25'd8322945, 9'd127);
    // assert reset with both elements still in the pipeline
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
    step(1'b1, 8'hFD, 16'd40000, 25'(-120000), 9'(-1));
    step(1'b1, 8'd127, 16'hFFFF, 25'd8322945, 9'd127);
    step(1'b1, 8'h80, 16'd0, 25'd0, 9'd0);
    step(1'b1, 8'hFF, 16'd32768, 25'(-32768), 9'd0);
    drain();
    $display("[t4] reset mid-stream, errors so far %0d", n_err);
  endtask

  initial begin
    if (!$value$plusargs("VECDIR=%s", vecdir))
      vecdir = $sformatf("tb/vectors/smx_scale/p%0d_n%0d", P, N_SEG);
    $display("tb_smx_scale: SCALE_LAT=%0d VECDIR=%s", LAT, vecdir);

    n_in  = 0;
    n_out = 0;
    n_err = 0;
    cur_set = "init";
    clear_hist();
    rst_n    = 1'b0;
    in_valid = 1'b0;
    q_in     = '0;
    k_in     = '0;
    repeat (3) @(negedge clk);
    if (out_valid !== 1'b0) report("out_valid during initial reset");
    rst_n = 1'b1;

    run_file("t3");
    run_file("t1");
    run_file("t2");
    reset_test();

    if (n_err == 0 && n_in == n_out)
      $display("TB_RESULT: PASS  %0d elements checked", n_out);
    else
      $display("TB_RESULT: FAIL  errors=%0d  in=%0d out=%0d", n_err, n_in, n_out);
    $finish;
  end

endmodule
