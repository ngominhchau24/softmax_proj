// smx_buf.sv - 8192-byte simple dual-port buffer, used twice (X_BUF, Y_BUF).
//
// BANKS = P/4 banks of 32-bit words, DEPTH = 8192/P words per bank. One write port
// (per-bank enable, shared byte enable) and one read port. Registered read: data of
// rd_addr presented in cycle n appears on rd_data in cycle n+1 (= smx_pkg::BUF_LAT).
// Reading and writing the same address in one cycle returns the OLD data (inferred
// M10K read-during-write behaviour is not relied upon beyond that).
// No reset, no initial: unwritten words read X in simulation.
//
// Memory coding (docs/spec/05-cross-block.md section 4.7, mandatory): one
// logic [7:0] mem [0:DEPTH-1] per bank and per byte lane inside nested generate.
// A packed word array such as logic [3:0][7:0] mem [DEPTH] inside generate is silently
// turned into flip-flops by Quartus 18.1.
module smx_buf #(
  parameter int P      = smx_pkg::P,                 // 4, 8 or 16
  parameter int BANKS  = P / 4,
  parameter int DEPTH  = 8192 / P,
  parameter int ADDR_W = $clog2(8192 / P)
) (
  input  logic                    clk,
  input  logic [BANKS-1:0]        wr_en,             // one bit per bank
  input  logic [3:0]              wr_be,             // byte enable, shared by active banks
  input  logic [ADDR_W-1:0]       wr_addr,
  input  logic [BANKS-1:0][31:0]  wr_data,           // bank 0 at the low bits
  input  logic [ADDR_W-1:0]       rd_addr,
  output logic [BANKS-1:0][31:0]  rd_data            // bank 0 at the low bits, lane 0 at [7:0]
);

  genvar b;
  genvar i;

  generate
    for (b = 0; b < BANKS; b = b + 1) begin : g_bank
      for (i = 0; i < 4; i = i + 1) begin : g_byte
        logic [7:0] mem [0:DEPTH-1];
        always_ff @(posedge clk) begin
          if (wr_en[b] & wr_be[i]) mem[wr_addr] <= wr_data[b][8*i +: 8];
          rd_data[b][8*i +: 8] <= mem[rd_addr];
        end
      end
    end
  endgenerate

endmodule
