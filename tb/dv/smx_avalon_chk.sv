// smx_avalon_chk.sv - bus-level checker for the Avalon-MM slave s0 of smx_avalon (simulation only).
//
// Instantiated by smx_dv_env when AVALON = 1. Two rules, judged every cycle:
//   A1  transparency (REQ-IF-06, REQ-IF-02): the wrapper only renames signals, so its read data
//       and status outputs must equal, cycle for cycle and bit for bit (X included), those of a
//       bare smx_core that receives the same commands. Any added logic or latency shows here.
//   A2  no X or Z on s0_readdata when readdatavalid (REQ-VER-03). The slave has a fixed read
//       latency and no readdatavalid pin; the Avalon interconnect derives it as s0_read delayed
//       by readLatency = 2 cycles, and this checker does the same. As in rule R8 of
//       smx_core_chk, only reads of registers and undefined addresses are judged: X_BUF and
//       Y_BUF words that were never written are X by design, and REQ-IF-09 leaves LEN, ROWS and
//       SCALE_K undefined while BUSY.
`timescale 1ns/1ps

module smx_avalon_chk (
  input logic        clk,
  input logic        reset_n,
  // the slave under test
  input logic [12:0] s0_address,
  input logic        s0_read,
  input logic [31:0] s0_readdata,
  input logic        status_busy,
  input logic        status_done,
  input logic        status_err,
  // the reference core, driven with the same commands
  input logic [31:0] ref_readdata,
  input logic        ref_busy,
  input logic        ref_done,
  input logic        ref_err
);

  import smx_dv_pkg::*;

  localparam int MAX_MSG = 20;

  int n_err = 0;
  int n_cmp = 0;     // cycles compared with the reference core (A1)
  int n_rdv = 0;     // readdatavalid cycles checked for X (A2)

  task automatic fail(input string msg);
    n_err++;
    if (n_err <= MAX_MSG) $display("ERROR [avalon chk %0t] %s", $time, msg);
  endtask

  logic rd_now;
  assign rd_now = s0_read && ((s0_address < 13'(A_XBUF)) || (s0_address >= 13'(A_UNDEF_HI)))
                  && !(status_busy && (s0_address == 13'(A_LEN) || s0_address == 13'(A_ROWS)
                                       || s0_address == 13'(A_SCALE_K)));

  logic [ACC_RD_LAT-1:0] rdv_pipe;     // rdv_pipe[ACC_RD_LAT-1]: readdatavalid of a judged read

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      rdv_pipe <= '0;
    end else begin
      // A1
      n_cmp++;
      if (s0_readdata !== ref_readdata)
        fail($sformatf("A1: s0_readdata %h differs from the bare core %h", s0_readdata, ref_readdata));
      if ({status_busy, status_done, status_err} !== {ref_busy, ref_done, ref_err})
        fail($sformatf("A1: status %b%b%b differs from the bare core %b%b%b",
                       status_busy, status_done, status_err, ref_busy, ref_done, ref_err));
      // A2
      if (rdv_pipe[ACC_RD_LAT-1]) begin
        n_rdv++;
        if ($isunknown(s0_readdata)) fail($sformatf("A2: X in s0_readdata %h when readdatavalid", s0_readdata));
      end
      rdv_pipe <= {rdv_pipe[ACC_RD_LAT-2:0], rd_now};
    end
  end

endmodule
