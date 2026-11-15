# wave_dv.do - wave window for a DV test (tb_smx_dv_*): the ports of smx_core and the checker counters.
# Used by "make dvview testname=tb_smx_dv_<test>", which sets the Tcl variable TOP to the test name
# before calling this file; the environment instance is always <top>/env.
# By hand, in the ModelSim transcript:   set TOP tb_smx_dv_proto;  do wave_dv.do
# To jump to the event a test is about, type one of these in the ModelSim transcript
# (times are for P = 8, N_SEG = 8, SEED = 1, the same windows as the figures of the report):
#   tb_smx_dv_sanity    wave zoom range 205ns 1025ns        first run: START, BUSY, STATUS read
#   tb_smx_dv_ver02     wave zoom range 40ns 160ns          X_BUF written with a garbage tail
#   tb_smx_dv_proto     wave zoom range 30ns 170ns          START with LEN = 0: DONE and ERR
#   tb_smx_dv_proto     wave zoom range 22530ns 22680ns     START in the last BUSY cycle
#   tb_smx_dv_latency   wave zoom range 55ns 745ns          shortest run, CYCLE_CNT read
#   tb_smx_dv_reg       wave zoom range 240ns 310ns         LEN written with byteenable 0101
#   tb_smx_dv_random    wave zoom range 957770ns 957940ns   reset in the middle of a run

if {![info exists TOP]} {
  echo "wave_dv.do: set TOP to the test name first, for example:  set TOP tb_smx_dv_proto"
  return
}

add wave -divider "clock and reset"
add wave /$TOP/env/clk
add wave /$TOP/env/rst_n
add wave -divider "acc port"
add wave /$TOP/env/acc_write
add wave /$TOP/env/acc_read
add wave -radix hexadecimal /$TOP/env/acc_addr
add wave -radix binary      /$TOP/env/acc_byteenable
add wave -radix hexadecimal /$TOP/env/acc_writedata
add wave -radix hexadecimal /$TOP/env/acc_readdata
add wave -divider "status"
add wave /$TOP/env/status_busy
add wave /$TOP/env/status_done
add wave /$TOP/env/status_err
add wave -divider "DV"
add wave -radix unsigned /$TOP/env/busy_cnt
add wave -radix unsigned /$TOP/env/dut/u_dv_chk/n_err
add wave -radix unsigned /$TOP/env/dut/u_dv_chk/n_start
add wave -radix unsigned /$TOP/env/dut/u_dv_chk/n_start_busy
add wave -radix unsigned /$TOP/env/dut/u_dv_chk/n_start_bad
# show only the last part of each name (acc_addr, not /tb_smx_dv_x/env/acc_addr)
configure wave -signalnamewidth 1
wave zoom full
