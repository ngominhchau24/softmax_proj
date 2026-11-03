// smx_divider.sv - Rcp = floor(2^RECIP_SH / sum), restoring divider, one quotient bit per cycle.
//
// Bit-exact with reciprocal() in model/softmax_ref.py (spec: docs/spec/blocks/smx_divider.md):
//   rem0 = 2^(RECIP_SH - RCP_W)                       (2^13)
//   repeat RCP_W times: t = 2*rem; bit = (t >= sum); rem = bit ? t - sum : t; q = {q, bit}
// Legal input: 2^14 <= sum <= 2^24 (so rem < sum <= 2^24 always, rem fits 24 bits).
// Timing (cross-block.md 4.5), start at cycle s: load at the end of s, iterate in s+1..s+RCP_W,
// done (one cycle) and the final rcp_out at s+DIV_LAT. rcp_out changes only at done.
// A start while busy restarts the division (undefined use, but harmless).
module smx_divider (
  input  logic                          clk,
  input  logic                          rst_n,
  input  logic                          start,     // one-cycle pulse, sum_in sampled here
  input  logic [smx_pkg::SUM_W-1:0]     sum_in,    // 2^14 <= sum <= 2^24
  output logic                          done,      // one-cycle pulse, DIV_LAT cycles after start
  output logic [smx_pkg::RCP_W-1:0]     rcp_out    // valid from done, held until the next done
);

  localparam int SUM_W  = smx_pkg::SUM_W;
  localparam int RCP_W  = smx_pkg::RCP_W;
  localparam int REM_W  = SUM_W - 1;                          // rem < sum <= 2^24
  localparam int CNT_W  = $clog2(RCP_W);
  localparam logic [REM_W-1:0] REM_INIT = REM_W'(1) << (smx_pkg::RECIP_SH - RCP_W);
  localparam logic [CNT_W-1:0] CNT_LAST = CNT_W'(RCP_W - 1);

  logic [SUM_W-1:0]  sum_q;
  logic [REM_W-1:0]  rem_q;
  logic [RCP_W-2:0]  quo_q;        // RCP_W-1 bits decided so far; the last bit goes straight to rcp_out
  logic [RCP_W-1:0]  rcp_q;
  logic [CNT_W-1:0]  cnt_q;
  logic              busy_q;
  logic              done_q;

  logic [SUM_W-1:0]  twice;
  logic [SUM_W:0]    diff;         // 26 bit: bit 25 is the borrow
  logic              ge;
  logic              last;

  assign twice = {rem_q, 1'b0};
  assign diff  = {1'b0, twice} - {1'b0, sum_q};
  assign ge    = ~diff[SUM_W];
  assign last  = busy_q & (cnt_q == CNT_LAST) & ~start;

  // Data registers, no reset
  always_ff @(posedge clk) begin
    if (start) begin
      sum_q <= sum_in;
      rem_q <= REM_INIT;
    end else begin
      rem_q <= ge ? diff[REM_W-1:0] : twice[REM_W-1:0];
    end
    quo_q <= {quo_q[RCP_W-3:0], ge};
    if (last) rcp_q <= {quo_q, ge};
  end

  // Control, reset
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_q <= 1'b0;
      cnt_q  <= '0;
      done_q <= 1'b0;
    end else begin
      done_q <= last;
      if (start) begin
        busy_q <= 1'b1;
        cnt_q  <= '0;
      end else if (busy_q) begin
        cnt_q <= cnt_q + 1'b1;
        if (cnt_q == CNT_LAST) busy_q <= 1'b0;
      end
    end
  end

  assign done    = done_q;
  assign rcp_out = rcp_q;

endmodule
