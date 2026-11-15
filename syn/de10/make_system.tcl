# make_system.tcl - builds the Platform Designer demo system for the DE10-Standard (no HPS):
#   Clock Source (CLOCK_50) + JTAG to Avalon Master Bridge + smx (ip/smx_hw.tcl).
# The JTAG master reaches smx at base 0x0, so System Console offsets equal requirements 5.2 offsets.
# Run through syn/de10/build.sh (uses qsys-script with ip/ on the search path).
package require -exact qsys 18.1

create_system smx_system
set_project_property DEVICE_FAMILY "Cyclone V"
set_project_property DEVICE 5CSXFC6D6F31C6

add_instance clk_0 clock_source
set_instance_parameter_value clk_0 clockFrequency 50000000
set_instance_parameter_value clk_0 clockFrequencyKnown true
set_instance_parameter_value clk_0 resetSynchronousEdges DEASSERT

add_instance jtag_master altera_jtag_avalon_master
add_instance smx_0 smx

add_connection clk_0.clk       jtag_master.clk
add_connection clk_0.clk       smx_0.clock
add_connection clk_0.clk_reset jtag_master.clk_reset
add_connection clk_0.clk_reset smx_0.reset
add_connection jtag_master.master smx_0.s0
set_connection_parameter_value jtag_master.master/smx_0.s0 baseAddress 0x0

add_interface clk clock sink
set_interface_property clk EXPORT_OF clk_0.clk_in
add_interface reset reset sink
set_interface_property reset EXPORT_OF clk_0.clk_in_reset
add_interface status conduit end
set_interface_property status EXPORT_OF smx_0.status

save_system smx_system.qsys
