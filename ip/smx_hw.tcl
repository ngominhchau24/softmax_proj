# smx_hw.tcl - Platform Designer component for the smx softmax accelerator (REQ-IF-11).
# Interfaces: clock, reset (reset_n), Avalon-MM slave s0 (words, readLatency 2, no waitrequest,
# no burst, 4-bit byteenable), conduit status (busy/done/err).
package require qsys

set_module_property NAME             smx
set_module_property DISPLAY_NAME     "smx integer-only softmax accelerator"
set_module_property VERSION          1.0
set_module_property GROUP            "Accelerators"
set_module_property DESCRIPTION      "Row-wise INT8 softmax, UINT8 output, scale 1/256"
set_module_property INTERNAL         false
set_module_property EDITABLE         false
set_module_property ELABORATION_CALLBACK elaborate

# ---- files (paths are relative to this tcl file) ----
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" "Quartus Synthesis"
set_fileset_property QUARTUS_SYNTH TOP_LEVEL smx_avalon
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
foreach f {
  ../rtl/pkg/smx_pkg.sv
  ../rtl/core/smx_delay.sv
  ../rtl/core/smx_exp2.sv
  ../rtl/core/smx_scale.sv
  ../rtl/core/smx_sumacc.sv
  ../rtl/core/smx_divider.sv
  ../rtl/core/smx_maxtree.sv
  ../rtl/core/smx_norm.sv
  ../rtl/core/smx_buf.sv
  ../rtl/core/smx_ctrl.sv
  ../rtl/core/smx_csr.sv
  ../rtl/core/smx_core.sv
  ../rtl/avalon/smx_avalon.sv
} {
  add_fileset_file [file tail $f] SYSTEM_VERILOG PATH $f
}

# ---- parameters (passed to smx_avalon; defaults are the submission configuration) ----
add_parameter P INTEGER 8
set_parameter_property P ALLOWED_RANGES {4 8 16}
set_parameter_property P HDL_PARAMETER true
set_parameter_property P DISPLAY_NAME "Lanes (P)"

add_parameter N_SEG INTEGER 8
set_parameter_property N_SEG ALLOWED_RANGES {4 8 16}
set_parameter_property N_SEG HDL_PARAMETER true
set_parameter_property N_SEG DISPLAY_NAME "PWL segments (N_SEG)"

# ---- interfaces ----
add_interface clock clock end
set_interface_property clock clockRate 0
add_interface_port clock clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset reset_n reset_n Input 1

add_interface s0 avalon end
set_interface_property s0 addressUnits WORDS
set_interface_property s0 associatedClock clock
set_interface_property s0 associatedReset reset
set_interface_property s0 bitsPerSymbol 8
set_interface_property s0 burstOnBurstBoundariesOnly false
set_interface_property s0 explicitAddressSpan 0
set_interface_property s0 holdTime 0
set_interface_property s0 setupTime 0
set_interface_property s0 timingUnits Cycles
set_interface_property s0 readLatency 2
set_interface_property s0 readWaitTime 0
set_interface_property s0 writeWaitTime 0
set_interface_property s0 maximumPendingReadTransactions 0
add_interface_port s0 s0_address     address     Input  13
add_interface_port s0 s0_write       write       Input  1
add_interface_port s0 s0_writedata   writedata   Input  32
add_interface_port s0 s0_byteenable  byteenable  Input  4
add_interface_port s0 s0_read        read        Input  1
add_interface_port s0 s0_readdata    readdata    Output 32

add_interface status conduit end
set_interface_property status associatedClock clock
set_interface_property status associatedReset ""
add_interface_port status status_busy busy Output 1
add_interface_port status status_done done Output 1
add_interface_port status status_err  err  Output 1

proc elaborate {} {
}
