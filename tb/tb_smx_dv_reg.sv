// tb_smx_dv_reg.sv - DV test 5: register and buffer access rules of smx_core (simulation only).
//
//   REQ-IF-03  byte enables on LEN, ROWS, SCALE_K and X_BUF, all 16 patterns; reads return the
//              whole word
//   REQ-IF-07  little-endian packing, 4 elements per word: rows written one element at a time
//              through single byte lanes must give the golden Y
//   REQ-IF-08  undefined addresses read 0 and ignore writes; read-only registers and Y_BUF
//              ignore writes; no address aliases onto a register
// Vectors: model/vec_dv_reg.py (one-hot rows that mark each byte lane).
// Run from sim/:  make testname=tb_smx_dv_reg [P=8] [N_SEG=8]
`timescale 1ns/1ps

module tb_smx_dv_reg;

  parameter int P     = 8;
  parameter int N_SEG = 8;

  import smx_dv_pkg::*;

  smx_dv_env #(.P(P), .N_SEG(N_SEG)) env ();

  // byte-wise merge of a write with byte enables
  function automatic logic [31:0] merge(input logic [31:0] old, input logic [31:0] data,
                                        input logic [3:0] be);
    logic [31:0] m;
    m = old;
    for (int b = 0; b < 4; b++) if (be[b]) m[b*8 +: 8] = data[b*8 +: 8];
    return m;
  endfunction

  // ---- REQ-IF-03 on one R/W register: field = bits of the register that exist ----
  task automatic reg_byte_enables(input string name, input int addr, input logic [31:0] field);
    logic [31:0] d, a, b;
    for (int be = 0; be < 16; be++) begin
      a = 32'hA5A5_A5A5 ^ {4{8'(be * 17)}};
      b = ~a;
      env.sb.ctx = $sformatf("%s byteenable=%b", name, 4'(be));
      env.bfm.write(addr, a, 4'hF);
      env.bfm.write(addr, b, 4'(be));
      env.bfm.read(addr, d);
      env.sb.check32({name, " after a partial write"}, d, merge(a, b, 4'(be)) & field);
    end
  endtask

  // ---- REQ-IF-03 on X_BUF words in every bank and in the first and last row ----
  task automatic xbuf_byte_enables();
    logic [31:0] d, a, b;
    int w;
    for (int k = 0; k < 2 * P; k++) begin
      // consecutive words cover every bank; alternate between row 0 and the last row
      w = (k % 2 == 0) ? k : (R_MAX - 1) * ROW_WORDS + ROW_WORDS - 1 - k;
      for (int be = 0; be < 16; be++) begin
        a = 32'h1234_5678 + 32'(k * 16 + be);
        b = ~a;
        env.sb.ctx = $sformatf("X_BUF word %0d byteenable=%b", w, 4'(be));
        env.bfm.write(A_XBUF + w, a, 4'hF);
        env.bfm.write(A_XBUF + w, b, 4'(be));
        env.bfm.read(A_XBUF + w, d);
        env.sb.check32("X_BUF word after a partial write", d, merge(a, b, 4'(be)));
      end
    end
  endtask

  // ---- REQ-IF-08 ----
  task automatic undefined_and_readonly();
    logic [31:0] d, hw;
    int a;
    env.sb.ctx = "undefined_addresses";
    env.bfm.write(A_LEN,     32'd100,  4'hF);
    env.bfm.write(A_ROWS,    32'd7,    4'hF);
    env.bfm.write(A_SCALE_K, 32'h1234, 4'hF);
    env.bfm.read(A_HWPARAM, hw);
    // undefined words: the hole behind the registers, addresses that would alias a register if
    // the decoder dropped address bits, and the region above Y_BUF
    for (int k = 0; k < 64; k++) begin
      case (k % 8)
        0:       a = 7 + (k / 8);                         // 7, 8, 9, ... right behind HW_PARAM
        1:       a = 'h008 + (k % 5);                     // alias of words 0..4 with bit 3 set
        2:       a = 'h7FF - (k / 8);                     // last words below X_BUF
        3:       a = 'h100 * (1 + (k / 8) % 7) + A_LEN;   // LEN with a higher address bit set
        4:       a = A_UNDEF_HI + (k / 8);                // first words above Y_BUF
        5:       a = A_UNDEF_HI + A_ROWS + 'h100 * (k / 8);
        6:       a = 'h1FFF - (k / 8);                    // top of the address space
        default: a = A_UNDEF_HI + (env.rnd() % 'h800);
      endcase
      env.bfm.write(a, 32'hFFFF_FFFF, 4'hF);
      env.bfm.read(a, d);
      env.sb.check32($sformatf("undefined word %h", a), d, 32'h0);
    end
    // read-only registers
    env.sb.ctx = "read_only_registers";
    env.bfm.write(A_STATUS,  32'hFFFF_FFFF, 4'hF);
    env.bfm.write(A_CYCLE,   32'hFFFF_FFFF, 4'hF);
    env.bfm.write(A_HWPARAM, 32'h0,         4'hF);
    env.bfm.write(A_CTRL,    32'hFFFF_FFFE, 4'hF);        // bit 0 clear: not a START
    env.bfm.read(A_HWPARAM, d);  env.sb.check32("HW_PARAM after a write", d, hw);
    env.bfm.read(A_CTRL, d);     env.sb.check32("CTRL reads 0", d, 32'h0);
    env.sb.check1("BUSY after CTRL write without bit 0", env.status_busy, 1'b0);
    // nothing above reached a real register
    env.bfm.read(A_LEN, d);      env.sb.check32("LEN after the undefined writes",     d, 32'd100);
    env.bfm.read(A_ROWS, d);     env.sb.check32("ROWS after the undefined writes",    d, 32'd7);
    env.bfm.read(A_SCALE_K, d);  env.sb.check32("SCALE_K after the undefined writes", d, 32'h1234);
  endtask

  // ---- Y_BUF is read-only: writes after a run change nothing ----
  task automatic ybuf_read_only();
    string base;
    base = env.sb.ctx;
    env.sb.ctx = {base, " Y_BUF write"};
    for (int r = 0; r < env.sb.R; r++)
      for (int w = 0; w < (env.sb.L + 3) / 4; w++)
        env.bfm.write(A_YBUF + r * ROW_WORDS + w, 32'h5A5A_5A5A, 4'hF);
    env.check_y();
    env.sb.ctx = base;
  endtask

  initial begin
    bit ok;
    logic [31:0] d;
    int n_bytewise;

    env.init("tb_smx_dv_reg", "dv.hex");
    n_bytewise = 0;

    reg_byte_enables("LEN",     A_LEN,     32'h0000_03FF);
    reg_byte_enables("ROWS",    A_ROWS,    32'h0000_001F);
    reg_byte_enables("SCALE_K", A_SCALE_K, 32'h0000_FFFF);
    xbuf_byte_enables();
    undefined_and_readonly();

    // REQ-IF-07 and REQ-IF-03 together: element-by-element writes, then whole words, same Y
    env.sb.next_run(ok);
    while (ok) begin
      env.x_mode = 2;
      env.run_and_check();
      ybuf_read_only();
      env.x_mode = 1;
      env.run_and_check();
      n_bytewise++;
      env.sb.next_run(ok);
    end

    // STATUS reads back DONE, the last run was legal: the status bits sit at [2:0], rest is 0
    env.sb.ctx = "status_word";
    env.bfm.read(A_STATUS, d);
    env.sb.check32("STATUS after the last run", d, ST_DONE);

    env.finish($sformatf("%0d runs written element by element, %0d writes, %0d reads",
                         n_bytewise, env.bfm.n_wr, env.bfm.n_rd));
  end

endmodule
