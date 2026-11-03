// tb_smx_buf.sv - self-checking unit testbench for smx_buf (simulation only).
//
// smx_buf has no arithmetic, so the testbench keeps its own byte-wise shadow array
// and predicts every read: data of rd_addr driven in cycle n must appear on
// rd_data exactly smx_pkg::BUF_LAT cycles later. Unwritten bytes must read X in
// simulation (checked with !==). A read of the address being written in the same
// cycle is not checked (read-during-write is don't-care on M10K).
// Takes P as a parameter (N_SEG is declared for the common flow and unused).
// Prints "TB_RESULT: PASS" or "TB_RESULT: FAIL".
`timescale 1ns/1ps

module tb_smx_buf;

  parameter int P     = smx_pkg::P;
  parameter int N_SEG = smx_pkg::N_SEG;  // unused

  localparam int LAT     = smx_pkg::BUF_LAT;
  localparam int BANKS   = P / 4;
  localparam int DEPTH   = 8192 / P;
  localparam int ADDR_W  = $clog2(8192 / P);
  localparam int LANES   = BANKS * 4;
  localparam int MAX_MSG = 20;

  logic                   clk = 1'b0;
  logic [BANKS-1:0]       wr_en;
  logic [3:0]             wr_be;
  logic [ADDR_W-1:0]      wr_addr;
  logic [BANKS-1:0][31:0] wr_data;
  logic [ADDR_W-1:0]      rd_addr;
  logic [BANKS-1:0][31:0] rd_data;

  always #5 clk = ~clk;  // 100 MHz

  // flat view: part-selects on the 2-D packed port would index banks, not bytes
  logic [BANKS*32-1:0] rd_flat;
  assign rd_flat = rd_data;

  smx_buf #(.P(P)) dut (.*);

  // shadow memory, one byte per lane and word
  logic [7:0] sh  [LANES][DEPTH];
  bit         shk [LANES][DEPTH];   // byte has been written

  // expectation history: hist_*[i] was made i+1 cycles ago
  logic [LANES*8-1:0] hist_d  [LAT];   // expected bytes
  logic [LANES-1:0]   hist_k  [LAT];   // byte known (written)
  bit                 hist_dc [LAT];   // don't care (read during write)
  bit                 hist_v  [LAT];   // a read was driven
  int                 hist_a  [LAT];

  int    n_in, n_chk, n_err;
  string cur_set;

  function automatic string hexw(input logic [BANKS*32-1:0] w);
    return $sformatf("%h", w);
  endfunction

  task automatic report(input string what);
    n_err++;
    if (n_err <= MAX_MSG)
      $display("ERROR [%s] %s: rd_addr=%0d exp=%h known=%b got=%h", cur_set, what,
               hist_a[LAT-1], hist_d[LAT-1], hist_k[LAT-1], rd_flat);
  endtask

  // Called right after a falling edge. Check rd_data against the read driven LAT cycles
  // ago, predict the read driven now, apply the write to the shadow, drive the pins.
  task automatic step(input logic [BANKS-1:0] we, input logic [3:0] be,
                      input int wa, input logic [BANKS*32-1:0] wd, input int ra);
    logic [LANES*8-1:0] ed;
    logic [LANES-1:0]   ek;
    bit                 dc;
    // check
    if (hist_v[LAT-1] && !hist_dc[LAT-1]) begin
      n_chk++;
      for (int l = 0; l < LANES; l++) begin
        if (hist_k[LAT-1][l]) begin
          if (rd_flat[8*l +: 8] !== hist_d[LAT-1][8*l +: 8]) begin
            report($sformatf("byte lane %0d", l));
            break;
          end
        end else begin
          if (^rd_flat[8*l +: 8] !== 1'bx) begin
            report($sformatf("unwritten byte lane %0d not X", l));
            break;
          end
        end
      end
    end
    // predict read (old contents, before this cycle's write)
    dc = 1'b0;
    for (int l = 0; l < LANES; l++) begin
      ed[8*l +: 8] = sh[l][ra];
      ek[l]        = shk[l][ra];
      if (we[l/4] && be[l%4] && wa == ra) dc = 1'b1;
    end
    for (int i = LAT-1; i > 0; i--) begin
      hist_d[i] = hist_d[i-1]; hist_k[i] = hist_k[i-1]; hist_dc[i] = hist_dc[i-1];
      hist_v[i] = hist_v[i-1]; hist_a[i] = hist_a[i-1];
    end
    hist_d[0] = ed; hist_k[0] = ek; hist_dc[0] = dc; hist_v[0] = 1'b1; hist_a[0] = ra;
    // apply write
    for (int l = 0; l < LANES; l++)
      if (we[l/4] && be[l%4]) begin
        sh[l][wa]  = wd[8*l +: 8];
        shk[l][wa] = 1'b1;
      end
    wr_en   = we;
    wr_be   = be;
    wr_addr = ADDR_W'(wa);
    wr_data = wd;
    rd_addr = ADDR_W'(ra);
    n_in++;
    @(negedge clk);
  endtask

  task automatic idle(input int n);
    repeat (n) step('0, 4'h0, 0, '0, 0);
  endtask

  function automatic logic [BANKS*32-1:0] rnd_word();
    logic [BANKS*32-1:0] w;
    for (int i = 0; i < BANKS; i++) w[32*i +: 32] = $urandom;
    return w;
  endfunction

  // word whose byte at lane l is base + l (makes lane order visible)
  function automatic logic [BANKS*32-1:0] lane_word(input logic [7:0] base);
    logic [BANKS*32-1:0] w;
    for (int l = 0; l < LANES; l++) w[8*l +: 8] = base + 8'(l);
    return w;
  endfunction

  logic [BANKS-1:0] all_en;
  int               a;

  initial begin
    n_in = 0; n_chk = 0; n_err = 0; cur_set = "init";
    all_en = '1;
    for (int i = 0; i < LAT; i++) begin
      hist_d[i] = '0; hist_k[i] = '0; hist_dc[i] = 1'b0; hist_v[i] = 1'b0; hist_a[i] = 0;
    end
    for (int l = 0; l < LANES; l++)
      for (int w = 0; w < DEPTH; w++) begin sh[l][w] = 8'h00; shk[l][w] = 1'b0; end
    wr_en = '0; wr_be = '0; wr_addr = '0; wr_data = '0; rd_addr = '0;
    $display("tb_smx_buf: P=%0d BANKS=%0d DEPTH=%0d ADDR_W=%0d BUF_LAT=%0d",
             P, BANKS, DEPTH, ADDR_W, LAT);
    @(negedge clk);

    // T1: unwritten memory reads X (shadow marks it unknown)
    cur_set = "T1 unwritten";
    for (int i = 0; i < 8; i++) step('0, 4'h0, 0, '0, (i * 37) % DEPTH);
    idle(LAT + 1);

    // T2: lane order. All banks, all bytes, distinct byte per lane; explicit check too
    cur_set = "T2 lane order";
    step(all_en, 4'hF, 5, lane_word(8'h10), 0);
    step('0, 4'h0, 0, '0, 5);
    step('0, 4'h0, 0, '0, 5);   // rd_data now holds the word read at address 5
    for (int l = 0; l < LANES; l++)
      if (rd_flat[8*l +: 8] !== 8'h10 + 8'(l)) begin
        n_err++;
        $display("ERROR [T2] explicit lane order: lane %0d got %h exp %h", l,
                 rd_flat[8*l +: 8], 8'h10 + 8'(l));
      end
    if (rd_flat[7:0] !== 8'h10) begin n_err++; $display("ERROR [T2] lane 0 not at rd_flat[7:0]"); end
    idle(LAT + 1);

    // T3: each wr_en bit selects only its bank (fresh word per bank, others stay X)
    cur_set = "T3 bank select";
    for (int b = 0; b < BANKS; b++) begin
      logic [BANKS-1:0] one;
      one = '0; one[b] = 1'b1;
      step(one, 4'hF, 100 + b, rnd_word() | 32'h0000_0001, 100 + b);  // collision: unchecked read
      step('0, 4'h0, 0, '0, 100 + b);
    end
    idle(LAT + 1);
    // wr_en = 0 with be = F must not write
    step('0, 4'hF, 200, rnd_word(), 200);
    step('0, 4'h0, 0, '0, 200);
    idle(LAT + 1);

    // T4: each byte enable pattern writes only its bytes across all banks
    cur_set = "T4 byte enable";
    step(all_en, 4'hF, 300, rnd_word(), 300);              // base word
    for (int be = 0; be < 16; be++) begin
      step(all_en, 4'hF, 301 + be, '0, 301 + be);          // clear to 0
      step(all_en, 4'(be), 301 + be, ~'0, 301 + be);       // overwrite selected bytes with FF
      step('0, 4'h0, 0, '0, 301 + be);
    end
    for (int be = 0; be < 16; be++) begin                  // single-cycle be on fresh words
      step(all_en, 4'(be), 400 + be, rnd_word(), 400 + be);
      step('0, 4'h0, 0, '0, 400 + be);
    end
    idle(LAT + 1);

    // T5: all-bank full-word writes (Y_BUF use), then a sweep
    cur_set = "T5 all-bank";
    for (int w = 0; w < 64; w++) step(all_en, 4'hF, w, rnd_word(), (w + 1) % 64);
    for (int w = 0; w < 64; w++) step('0, 4'h0, 0, '0, w);
    idle(LAT + 1);

    // T6: first and last address
    cur_set = "T6 edges";
    step(all_en, 4'hF, 0, rnd_word(), 0);
    step(all_en, 4'hF, DEPTH-1, rnd_word(), DEPTH-1);
    step('0, 4'h0, 0, '0, 0);
    step('0, 4'h0, 0, '0, DEPTH-1);
    step('0, 4'h0, 0, '0, 0);
    step('0, 4'h0, 0, '0, DEPTH-1);
    // DEPTH-1 vs DEPTH-2 must not alias, 0 vs 1 neither
    step(all_en, 4'hF, DEPTH-2, rnd_word(), DEPTH-1);
    step(all_en, 4'hF, 1, rnd_word(), 0);
    step('0, 4'h0, 0, '0, DEPTH-2);
    step('0, 4'h0, 0, '0, 1);
    step('0, 4'h0, 0, '0, DEPTH-1);
    step('0, 4'h0, 0, '0, 0);
    idle(LAT + 1);

    // T7: read-after-write in the next cycle returns new data
    cur_set = "T7 raw";
    for (int w = 0; w < 32; w++) begin
      step(all_en, 4'hF, 450 + w, rnd_word(), 0);
      step('0, 4'h0, 0, '0, 450 + w);                      // read in the cycle right after
    end
    idle(LAT + 1);
    // overwrite then immediately read: new data, not the old one
    step(all_en, 4'hF, 490, lane_word(8'h20), 0);
    step(all_en, 4'hF, 490, lane_word(8'h80), 0);
    step('0, 4'h0, 0, '0, 490);
    idle(LAT + 1);

    // T8: continuous read, address changes every cycle, whole memory
    cur_set = "T8 stream";
    for (int w = 0; w < DEPTH; w++) step(all_en, 4'hF, w, rnd_word(), 0);
    for (int w = 0; w < DEPTH; w++) step('0, 4'h0, 0, '0, w);
    for (int w = 0; w < DEPTH; w++) step('0, 4'h0, 0, '0, DEPTH - 1 - w);
    for (int w = 0; w < DEPTH; w++) step('0, 4'h0, 0, '0, (w * 7 + 3) % DEPTH);
    idle(LAT + 1);

    // T9: random operations (small hot region to force collisions, then full range)
    cur_set = "T9 random";
    for (int n = 0; n < 200000; n++) begin
      int span;
      logic [BANKS-1:0] we;
      span = (n < 100000) ? 16 : DEPTH;
      for (int b = 0; b < BANKS; b++) we[b] = ($urandom % 3 == 0);
      if ($urandom % 4 == 0) we = '0;
      step(we, 4'($urandom), $urandom % span, rnd_word(), $urandom % span);
    end
    idle(LAT + 1);

    if (n_chk == 0) n_err++;
    if (n_err == 0)
      $display("TB_RESULT: PASS  P=%0d  %0d cycles, %0d reads checked", P, n_in, n_chk);
    else
      $display("TB_RESULT: FAIL  P=%0d  errors=%0d  cycles=%0d reads=%0d", P, n_err, n_in, n_chk);
    $finish;
  end

endmodule
