// tb_smx_exp2.sv - self-checking unit testbench for smx_exp2 (simulation only).
//
// Reads t1..t4.hex made by model/gen_vectors.py, drives one vector per cycle and
// checks out_valid and e_out bit-exact, with exactly smx_pkg::EXP2_LAT cycles of
// latency (T1..T5 of docs/spec/blocks/smx_exp2.md section 8). Then checks reset
// in the middle of a stream (T6). Prints "TB_RESULT: PASS" or "TB_RESULT: FAIL".
//
// Plusargs: +VECDIR=<dir> (default tb/vectors/smx_exp2/n<N_SEG>)
`timescale 1ns/1ps

module tb_smx_exp2;

  parameter int N_SEG = smx_pkg::N_SEG;

  localparam int LAT     = smx_pkg::EXP2_LAT;
  localparam int U_W     = smx_pkg::U_W;
  localparam int C_W     = smx_pkg::C_W;
  localparam int E_W     = smx_pkg::E_W;
  localparam int MAX_MSG = 20;

  logic                  clk = 1'b0;
  logic                  rst_n;
  logic                  in_valid;
  logic                  in_en;
  logic signed [U_W-1:0] u_in;
  logic signed [C_W-1:0] m_in;
  logic                  out_valid;
  logic [E_W-1:0]        e_out;

  always #5 clk = ~clk;  // 100 MHz

  smx_exp2 #(.N_SEG(N_SEG)) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_valid  (in_valid),
    .in_en     (in_en),
    .u_in      (u_in),
    .m_in      (m_in),
    .out_valid (out_valid),
    .e_out     (e_out)
  );

  // hist_*[i] holds the vector driven i+1 cycles ago
  logic           hist_v [LAT];
  logic [E_W-1:0] hist_e [LAT];
  logic [U_W-1:0] hist_u [LAT];
  logic [C_W-1:0] hist_m [LAT];
  logic           hist_en[LAT];
  int             hist_n [LAT];

  int    n_in, n_out, n_err;
  string vecdir;
  string cur_set;

  task automatic clear_hist();
    for (int i = 0; i < LAT; i++) begin
      hist_v[i] = 1'b0;
      hist_e[i] = '0;
      hist_u[i] = '0;
      hist_m[i] = '0;
      hist_en[i] = 1'b0;
      hist_n[i] = -1;
    end
  endtask

  task automatic report(input string what);
    n_err++;
    if (n_err <= MAX_MSG)
      $display("ERROR [%s] %s: vec#%0d en=%0b u=%h m=%h exp_v=%0b exp_e=%h got_v=%b got_e=%h",
               cur_set, what, hist_n[LAT-1], hist_en[LAT-1], hist_u[LAT-1], hist_m[LAT-1],
               hist_v[LAT-1], hist_e[LAT-1], out_valid, e_out);
  endtask

  // Called right after a falling edge: check the outputs against the vector
  // driven LAT cycles ago, drive the next vector, wait for the next falling edge.
  task automatic step(input logic v, input logic en, input logic [U_W-1:0] u,
                      input logic [C_W-1:0] m, input logic [E_W-1:0] e);
    if (out_valid !== hist_v[LAT-1])
      report("out_valid");
    else if (out_valid === 1'b1) begin
      n_out++;
      if (e_out !== hist_e[LAT-1])
        report("e_out");
    end

    for (int i = LAT-1; i > 0; i--) begin
      hist_v[i]  = hist_v[i-1];
      hist_e[i]  = hist_e[i-1];
      hist_u[i]  = hist_u[i-1];
      hist_m[i]  = hist_m[i-1];
      hist_en[i] = hist_en[i-1];
      hist_n[i]  = hist_n[i-1];
    end
    hist_v[0]  = v;
    hist_e[0]  = e;
    hist_u[0]  = u;
    hist_m[0]  = m;
    hist_en[0] = en;
    hist_n[0]  = n_in;

    in_valid = v;
    in_en    = en;
    u_in     = u;
    m_in     = m;
    if (v) n_in++;
    @(negedge clk);
  endtask

  task automatic drain();
    repeat (LAT + 1) step(1'b0, 1'b0, '0, '0, '0);
  endtask

  task automatic run_file(input string name);
    int          fd;
    int          cnt;
    string       line;
    logic [31:0] v, en, u, m, e;
    cur_set = name;
    cnt = 0;
    fd = $fopen({vecdir, "/", name, ".hex"}, "r");
    if (fd == 0) begin
      $display("ERROR: cannot open %s/%s.hex (run model/gen_vectors.py exp2 --n-seg %0d)",
               vecdir, name, N_SEG);
      n_err++;
      return;
    end
    while ($fgets(line, fd) != 0) begin
      if (line.len() < 2 || line[0] == "#") continue;
      if ($sscanf(line, "%h %h %h %h %h", v, en, u, m, e) != 5) begin
        $display("ERROR: bad line in %s.hex: %s", name, line);
        n_err++;
        continue;
      end
      step(v[0], en[0], u[U_W-1:0], m[C_W-1:0], e[E_W-1:0]);
      cnt++;
    end
    $fclose(fd);
    drain();
    $display("[%s] %0d vectors, errors so far %0d", name, cnt, n_err);
  endtask

  // T6: reset while elements are in flight. Expected values do not depend on N_SEG:
  // d = 0 -> 32768, d = -1 -> 32767, d = -15*2^16 -> 1, d = -16*2^16 -> 0 (cutoff).
  task automatic reset_test();
    int lost;
    cur_set = "t6";
    step(1'b1, 1'b1, 25'h0000000, 9'd0,  16'd32768);
    step(1'b1, 1'b1, 25'h1ffffff, 9'd0,  16'd32767);
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
    step(1'b1, 1'b1, 25'h0000000, 9'd0,  16'd32768);
    step(1'b1, 1'b1, 25'h1ffffff, 9'd0,  16'd32767);
    step(1'b1, 1'b1, 25'h0000000, 9'd15, 16'd1);
    step(1'b1, 1'b1, 25'h0000000, 9'd16, 16'd0);
    drain();
    $display("[t6] reset mid-stream, errors so far %0d", n_err);
  endtask

  initial begin
    if (!$value$plusargs("VECDIR=%s", vecdir))
      vecdir = $sformatf("tb/vectors/smx_exp2/n%0d", N_SEG);
    $display("tb_smx_exp2: N_SEG=%0d EXP2_LAT=%0d VECDIR=%s", N_SEG, LAT, vecdir);

    n_in  = 0;
    n_out = 0;
    n_err = 0;
    cur_set = "init";
    clear_hist();
    rst_n    = 1'b0;
    in_valid = 1'b0;
    in_en    = 1'b0;
    u_in     = '0;
    m_in     = '0;
    repeat (3) @(negedge clk);
    if (out_valid !== 1'b0) report("out_valid during initial reset");
    rst_n = 1'b1;

    run_file("t3");
    run_file("t1");
    run_file("t2");
    run_file("t4");
    reset_test();

    if (n_err == 0 && n_in == n_out)
      $display("TB_RESULT: PASS  N_SEG=%0d  %0d elements checked", N_SEG, n_out);
    else
      $display("TB_RESULT: FAIL  N_SEG=%0d  errors=%0d  in=%0d out=%0d", N_SEG, n_err, n_in, n_out);
    $finish;
  end

endmodule
