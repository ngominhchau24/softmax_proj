// smx_de10_top.sv - DE10-Standard top level for the smx demo system (no HPS).
// CLOCK_50 drives the Platform Designer system; KEY[0] is the active-low reset; LEDR[2:0] show
// busy / done / err. The JTAG to Avalon Master Bridge inside smx_system is driven from System
// Console over the on-board USB-Blaster II.
module smx_de10_top (
  input  logic       CLOCK_50,
  input  logic [1:0] KEY,       // KEY[0] = reset, active low (pressed = 0)
  output logic [2:0] LEDR       // [0] busy, [1] done, [2] err
);

  // Asynchronous assert, synchronous deassert: smx_core has no reset synchroniser
  // (docs/spec/07-open-decisions.md A2), so the one who drives rst_n must release it in step with clk.
  logic [1:0] rst_sync_q;
  logic       reset_n;
  always_ff @(posedge CLOCK_50 or negedge KEY[0]) begin
    if (!KEY[0]) rst_sync_q <= 2'b00;
    else         rst_sync_q <= {rst_sync_q[0], 1'b1};
  end
  assign reset_n = rst_sync_q[1];

  smx_system u_sys (
    .clk_clk       (CLOCK_50),
    .reset_reset_n (reset_n),
    .status_busy   (LEDR[0]),
    .status_done   (LEDR[1]),
    .status_err    (LEDR[2])
  );

endmodule
