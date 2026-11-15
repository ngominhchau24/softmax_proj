// smx_core_bind.sv - binds the REQ-VER-03 protocol checker into smx_core (simulation only).
//
// The bind sits inside a module, so it takes effect only in a testbench that instantiates
// smx_core_bind (tb/dv/smx_dv_env.sv does); the designer's unit testbenches are not touched.
// The checker instance is <path of smx_core>.u_dv_chk and connects to the DUT ports by name.
`timescale 1ns/1ps

module smx_core_bind;

  bind smx_core smx_core_chk u_dv_chk (
    .clk            (clk),
    .rst_n          (rst_n),
    .acc_addr       (acc_addr),
    .acc_write      (acc_write),
    .acc_writedata  (acc_writedata),
    .acc_byteenable (acc_byteenable),
    .acc_read       (acc_read),
    .acc_readdata   (acc_readdata),
    .status_busy    (status_busy),
    .status_done    (status_done),
    .status_err     (status_err)
  );

endmodule
