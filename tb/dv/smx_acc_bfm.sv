// smx_acc_bfm.sv - bus functional model for the acc_* port of smx_core (simulation only).
//
// Convention: every task is called at a falling clock edge and returns at a falling clock edge.
// Commands are driven at the falling edge, so the DUT samples them at the next rising edge without
// a race. One command per cycle; reads may be issued back to back.
// A read issued at falling edge T returns its data at falling edge T + ACC_RD_LAT (REQ-IF-02).
`timescale 1ns/1ps

module smx_acc_bfm (
  input  logic        clk,
  output logic [12:0] acc_addr,
  output logic        acc_write,
  output logic [31:0] acc_writedata,
  output logic [3:0]  acc_byteenable,
  output logic        acc_read,
  input  logic [31:0] acc_readdata
);

  import smx_dv_pkg::*;

  localparam int RBUF_WORDS = ROW_WORDS;       // longest burst: one full row

  logic [31:0] rbuf [RBUF_WORDS];              // data of the last read_burst, rbuf[j] = read j
  int          n_wr = 0;                       // commands issued, for the end-of-test summary
  int          n_rd = 0;

  initial begin
    acc_addr       = '0;
    acc_write      = 1'b0;
    acc_read       = 1'b0;
    acc_writedata  = '0;
    acc_byteenable = 4'hF;
  end

  // no command for n cycles
  task automatic idle(input int n);
    acc_write = 1'b0;
    acc_read  = 1'b0;
    repeat (n) @(negedge clk);
  endtask

  // one write, one cycle
  task automatic write(input int addr, input logic [31:0] data, input logic [3:0] be);
    acc_addr       = addr[12:0];
    acc_write      = 1'b1;
    acc_read       = 1'b0;
    acc_writedata  = data;
    acc_byteenable = be;
    @(negedge clk);
    acc_write = 1'b0;
    n_wr++;
  endtask

  // cnt reads at consecutive addresses, one per cycle; takes cnt + ACC_RD_LAT - 1 cycles
  task automatic read_burst(input int addr, input int cnt);
    int a;
    for (int i = 0; i < cnt + ACC_RD_LAT - 1; i++) begin
      if (i < cnt) begin
        a         = addr + i;
        acc_addr  = a[12:0];
        acc_read  = 1'b1;
        acc_write = 1'b0;
      end else begin
        acc_read = 1'b0;
      end
      @(negedge clk);
      if (i >= ACC_RD_LAT - 1) rbuf[i - (ACC_RD_LAT - 1)] = acc_readdata;
    end
    acc_read = 1'b0;
    n_rd += cnt;
  endtask

  // one read, ACC_RD_LAT cycles
  task automatic read(input int addr, output logic [31:0] data);
    read_burst(addr, 1);
    data = rbuf[0];
  endtask

endmodule
