// smx_core_chk.sv - protocol checker for the ports of smx_core, REQ-VER-03 (simulation only).
//
// Bound into the DUT by smx_core_bind.sv as dut.u_dv_chk; it only looks at the ports.
// Written as clocked procedural checks, not SVA properties, so it also runs on simulators without
// concurrent assertion support (ModelSim Intel FPGA Starter).
//
// Rules, from docs/requirements.md (REQ-VER-03, REQ-FUN-04) and design spec section 3.4. "START"
// is a write to CTRL with bit 0 set and byte lane 0 enabled. Outputs are registered, so a command
// in cycle n shows in cycle n + 1.
//   R1  no X or Z on the status pins
//   R2  BUSY and DONE are never 1 together; ERR is never 1 while BUSY
//   R3  START while idle with LEN in 1..L_MAX and ROWS in 1..R_MAX: next cycle BUSY=1, DONE=0, ERR=0
//   R4  START while idle with LEN or ROWS out of range: next cycle BUSY=0, DONE=1, ERR=1
//   R5  START while BUSY is ignored: the run goes on as if nothing was written
//   R6  without a START, an idle core stays idle and DONE, ERR keep their values (sticky)
//   R7  a run ends in one step: BUSY falls and DONE rises in the same cycle, never DONE first
//   R8  a read of a register or an undefined address never returns X, two cycles after the command
//       (LEN, ROWS, SCALE_K are left out while BUSY: REQ-IF-09 calls that access undefined)
// LEN and ROWS are not ports, so the checker keeps its own copy from the bus writes, with the byte
// enables and the rule that writes while BUSY are ignored (open-decisions B3).
`timescale 1ns/1ps

module smx_core_chk (
  input logic        clk,
  input logic        rst_n,
  input logic [12:0] acc_addr,
  input logic        acc_write,
  input logic [31:0] acc_writedata,
  input logic [3:0]  acc_byteenable,
  input logic        acc_read,
  input logic [31:0] acc_readdata,
  input logic        status_busy,
  input logic        status_done,
  input logic        status_err
);

  import smx_dv_pkg::*;

  localparam int MAX_MSG = 20;

  int n_err        = 0;
  int n_start      = 0;     // START commands seen
  int n_start_busy = 0;     // of them, while BUSY (R5)
  int n_start_bad  = 0;     // of them, idle with bad LEN or ROWS (R4)
  int n_rd_chk     = 0;     // reads checked for X (R8)

  task automatic fail(input string msg);
    n_err++;
    if (n_err <= MAX_MSG) $display("ERROR [chk %0t] %s", $time, msg);
  endtask

  // ---- copy of LEN and ROWS ----
  logic [9:0] len_s;
  logic [4:0] rows_s;

  // ---- this cycle ----
  logic start_now, cfg_bad_now, rd_now;
  assign start_now   = acc_write && (acc_addr == 13'(A_CTRL)) && acc_byteenable[0] && acc_writedata[0];
  assign cfg_bad_now = (len_s == 10'd0) || (len_s > 10'(L_MAX)) || (rows_s == 5'd0) || (rows_s > 5'(R_MAX));
  // reads that must be free of X
  assign rd_now = acc_read && ((acc_addr < 13'(A_XBUF)) || (acc_addr >= 13'(A_UNDEF_HI)))
                  && !(status_busy && (acc_addr == 13'(A_LEN) || acc_addr == 13'(A_ROWS)
                                       || acc_addr == 13'(A_SCALE_K)));

  // ---- previous cycle ----
  logic       p_valid;
  logic       p_busy, p_done, p_err, p_start, p_cfg_bad;
  logic [1:0] rd_pipe;      // rd_pipe[1]: a checked read was issued two cycles ago

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      p_valid <= 1'b0;
      len_s   <= '0;
      rows_s  <= '0;
      rd_pipe <= '0;
    end else begin
      // R1
      if ($isunknown({status_busy, status_done, status_err})) fail("R1: X or Z on a status pin");
      else begin
        // R2
        if (status_busy && status_done) fail("R2: BUSY and DONE both 1");
        if (status_busy && status_err)  fail("R2: ERR is 1 while BUSY");

        if (p_valid) begin
          if (p_start && !p_busy && !p_cfg_bad) begin
            // R3
            if (!(status_busy && !status_done && !status_err))
              fail($sformatf("R3: after a legal START busy=%b done=%b err=%b, want 1 0 0",
                             status_busy, status_done, status_err));
          end else if (p_start && !p_busy && p_cfg_bad) begin
            // R4
            if (!(!status_busy && status_done && status_err))
              fail($sformatf("R4: after START with bad LEN/ROWS busy=%b done=%b err=%b, want 0 1 1",
                             status_busy, status_done, status_err));
          end else if (!p_busy) begin
            // R6
            if (status_busy) fail("R6: BUSY rose without a START");
            if (status_done !== p_done) fail("R6: DONE changed without a START");
            if (status_err  !== p_err)  fail("R6: ERR changed without a START");
          end else begin
            // R5 and R7: the run continues or ends, with or without a START written meanwhile
            if (status_busy && status_done) ;                    // already reported by R2
            else if (!status_busy && !status_done)
              fail(p_start ? "R5: START while BUSY disturbed the run: BUSY fell without DONE"
                           : "R7: BUSY fell without DONE");
          end
        end
      end

      // R8
      if (rd_pipe[1]) begin
        n_rd_chk++;
        if ($isunknown(acc_readdata)) fail($sformatf("R8: X in acc_readdata %h", acc_readdata));
      end

      // counters
      if (start_now) begin
        n_start++;
        if (status_busy) n_start_busy++;
        else if (cfg_bad_now) n_start_bad++;
      end

      // state for the next cycle
      p_valid   <= 1'b1;
      p_busy    <= status_busy;
      p_done    <= status_done;
      p_err     <= status_err;
      p_start   <= start_now;
      p_cfg_bad <= cfg_bad_now;
      rd_pipe   <= {rd_pipe[0], rd_now};
      if (acc_write && !status_busy) begin
        if (acc_addr == 13'(A_LEN)) begin
          if (acc_byteenable[0]) len_s[7:0] <= acc_writedata[7:0];
          if (acc_byteenable[1]) len_s[9:8] <= acc_writedata[9:8];
        end
        if (acc_addr == 13'(A_ROWS) && acc_byteenable[0]) rows_s <= acc_writedata[4:0];
      end
    end
  end

endmodule
