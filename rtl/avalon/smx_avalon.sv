// smx_avalon.sv - thin Avalon-MM wrapper around smx_core (REQ-IF-01, REQ-IF-06, REQ-IF-10).
// Only renames signals: s0_* is the Avalon slave, acc_* is the core's access port.
// Avalon timing: word addressing, no burst, no waitrequest, fixed read latency 2
// (smx_core returns acc_readdata exactly ACC_RD_LAT = 2 cycles after acc_read).
// Reset: rst_n is asserted asynchronously; deassertion must be synchronous to clk and is the
// responsibility of whoever drives reset_n (docs/spec/07-open-decisions.md A2).
module smx_avalon #(
  parameter int P     = smx_pkg::P,       // lanes: 4, 8 or 16
  parameter int N_SEG = smx_pkg::N_SEG    // PWL segments: 4, 8 or 16
) (
  input  logic        clk,
  input  logic        reset_n,
  // Avalon-MM slave s0
  input  logic [12:0] s0_address,         // word address
  input  logic        s0_write,
  input  logic [31:0] s0_writedata,
  input  logic [3:0]  s0_byteenable,
  input  logic        s0_read,
  output logic [31:0] s0_readdata,
  // status conduit
  output logic        status_busy,
  output logic        status_done,
  output logic        status_err
);

  smx_core #(.P(P), .N_SEG(N_SEG)) u_core (
    .clk            (clk),
    .rst_n          (reset_n),
    .acc_addr       (s0_address),
    .acc_write      (s0_write),
    .acc_writedata  (s0_writedata),
    .acc_byteenable (s0_byteenable),
    .acc_read       (s0_read),
    .acc_readdata   (s0_readdata),
    .status_busy    (status_busy),
    .status_done    (status_done),
    .status_err     (status_err)
  );

endmodule
