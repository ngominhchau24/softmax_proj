// smx_ctrl.sv - row/group sequencer of smx_core (docs/spec/cross-block.md 4.9, 5).
//
// No arithmetic. Issues one group of P elements per cycle in pass 1 and pass 2 of
// every row, and steps between phases on events from the datapath (sum_last,
// div_done, y_last), never by counting datapath latency.
// grp_*, div_start, run_done and y_wr_addr are combinational from state and
// registers (no output register): registering y_wr_addr would store group g at g+1.
// Tags grp_pass2/first/last/en are forced to 0 when grp_valid = 0.
// Events must arrive at least one cycle after the cycle that triggers them
// (sum_last after the last group, div_done after div_start, y_last after the last
// pass-2 group), which holds for any datapath latency >= 1.
module smx_ctrl #(
  parameter int P      = smx_pkg::P,                 // 4, 8 or 16
  parameter int ADDR_W = $clog2(8192 / P)            // {r, g}
) (
  input  logic               clk,
  input  logic               rst_n,
  input  logic               start,       // from smx_csr, pulse in the first BUSY cycle
  input  logic [9:0]         len,         // L in 1..512, stable while busy
  input  logic [4:0]         rows,        // R in 1..16, stable while busy
  output logic               grp_valid,
  output logic               grp_pass2,
  output logic               grp_first,
  output logic               grp_last,
  output logic [P-1:0]       grp_en,
  output logic [ADDR_W-1:0]  grp_addr,    // {r, g}
  input  logic               sum_last,
  output logic               div_start,
  input  logic               div_done,
  input  logic               y_valid,
  input  logic               y_last,
  output logic [ADDR_W-1:0]  y_wr_addr,   // {r, yg}
  output logic               run_done
);

  localparam int LOGP = $clog2(P);
  localparam int GW   = ADDR_W - 4;       // bits of g inside the address (7 at P = 4)

  typedef enum logic [2:0] {
    S_IDLE     = 3'd0,
    S_P1_RUN   = 3'd1,
    S_P1_DRAIN = 3'd2,
    S_DIV      = 3'd3,
    S_DIV_WAIT = 3'd4,
    S_P2_RUN   = 3'd5,
    S_P2_DRAIN = 3'd6,
    S_NEXT_ROW = 3'd7
  } state_t;

  state_t         state_q;
  logic [3:0]     r_q;
  logic [GW-1:0]  g_q;
  logic [GW-1:0]  yg_q;

  // ---------------------------------------------------------------------------
  // Group geometry from len, no divider:
  //   G - 1   = floor((L - 1) / P)          last group index, up to 127
  //   lastrem = (L - 1) mod P               highest valid lane of the last group
  // ---------------------------------------------------------------------------
  logic [9:0]       len_m1;
  logic [7:0]       g_last_idx;             // 8 bit: G - 1 <= 127
  logic [LOGP-1:0]  last_lane;
  logic [P-1:0]     en_last;
  logic [7:0]       g_ext;                  // g_q widened to compare with g_last_idx
  logic             is_run;
  logic             is_last_grp;
  logic             is_last_row;
  logic [4:0]       rows_m1;

  assign len_m1     = len - 10'd1;
  assign g_last_idx = 8'(len_m1 >> LOGP);
  assign last_lane  = len_m1[LOGP-1:0];
  assign g_ext      = 8'(g_q);
  assign rows_m1    = rows - 5'd1;

  genvar j;
  generate
    for (j = 0; j < P; j++) begin : g_en
      assign en_last[j] = (j <= int'(last_lane));
    end
  endgenerate

  assign is_run      = (state_q == S_P1_RUN) || (state_q == S_P2_RUN);
  assign is_last_grp = (g_ext == g_last_idx);
  assign is_last_row = ({1'b0, r_q} == rows_m1);       // 5 bit: r + 1 would wrap at R = 16

  // ---------------------------------------------------------------------------
  // Outputs (combinational)
  // ---------------------------------------------------------------------------
  assign grp_valid = is_run;
  assign grp_pass2 = (state_q == S_P2_RUN);
  assign grp_first = is_run && (g_q == '0);
  assign grp_last  = is_run && is_last_grp;
  assign grp_en    = !is_run ? '0 : (is_last_grp ? en_last : {P{1'b1}});
  assign grp_addr  = {r_q, g_q};
  assign div_start = (state_q == S_DIV);
  assign y_wr_addr = {r_q, yg_q};
  assign run_done  = (state_q == S_NEXT_ROW) && is_last_row;

  // ---------------------------------------------------------------------------
  // Sequencing
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      r_q     <= '0;
      g_q     <= '0;
      yg_q    <= '0;
    end else begin
      // yg counts every y_valid in any state; cleared on start and in NEXT_ROW
      if (y_valid) yg_q <= yg_q + 1'b1;

      case (state_q)
        S_IDLE: begin
          if (start) begin
            state_q <= S_P1_RUN;
            r_q     <= '0;
            g_q     <= '0;
            yg_q    <= '0;
          end
        end
        S_P1_RUN: begin
          if (is_last_grp) begin
            g_q     <= '0;
            state_q <= S_P1_DRAIN;
          end else begin
            g_q <= g_q + 1'b1;
          end
        end
        S_P1_DRAIN: if (sum_last) state_q <= S_DIV;
        S_DIV:      state_q <= S_DIV_WAIT;
        S_DIV_WAIT: if (div_done) state_q <= S_P2_RUN;
        S_P2_RUN: begin
          if (is_last_grp) begin
            g_q     <= '0;
            state_q <= S_P2_DRAIN;
          end else begin
            g_q <= g_q + 1'b1;
          end
        end
        S_P2_DRAIN: if (y_last) state_q <= S_NEXT_ROW;
        S_NEXT_ROW: begin
          yg_q <= '0;
          g_q  <= '0;
          if (is_last_row) begin
            state_q <= S_IDLE;
          end else begin
            r_q     <= r_q + 4'd1;
            state_q <= S_P1_RUN;
          end
        end
        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule
