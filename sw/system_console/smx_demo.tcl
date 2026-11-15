# smx_demo.tcl - run the smx accelerator on the DE10-Standard over JTAG and check it against the golden model.
#
# Setup:  1. Program syn/release/smx_de10.sof (Quartus Programmer, USB-Blaster II).
#         2. python3 sw/system_console/gen_test_data.py        (only if smx_test_data.tcl is missing/outdated)
# Run:    system-console --script=sw/system_console/smx_demo.tcl
#         (system-console is in <Quartus>/quartus/sopc_builder/bin) or, in the System Console GUI:
#         source sw/system_console/smx_demo.tcl
#
# Address map (byte offsets from the JTAG master, base 0x0; docs/requirements.md 5.2):
#   0x0000 CTRL (bit0 START)   0x0004 STATUS (BUSY[0] DONE[1] ERR[2])   0x0008 LEN   0x000C ROWS
#   0x0010 SCALE_K   0x0014 CYCLE_CNT   0x0018 HW_PARAM   0x2000 X_BUF   0x4000 Y_BUF   (row stride 512 B)
# Written for the plain Tcl subset (no dict, no lmap) so it also runs in older System Console versions.
# Prints "SMX_DEMO_RESULT: PASS" or "SMX_DEMO_RESULT: FAIL" on the last line.

set SMX_BASE     0x0
set SMX_CTRL     0x0000
set SMX_STATUS   0x0004
set SMX_LEN      0x0008
set SMX_ROWS     0x000C
set SMX_K        0x0010
set SMX_CYCLES   0x0014
set SMX_HWPARAM  0x0018
set SMX_XBUF     0x2000
set SMX_YBUF     0x4000
set SMX_ROWSTEP  512
set SMX_ROW_OVERHEAD 54    ;# smx_pkg::ROW_OVERHEAD, T_row = 2*ceil(L/P) + 54
set SMX_POLL_MAX 2000

proc hex2int {s} {
    set s [string tolower [string trim $s]]
    if {[string equal [string range $s 0 1] "0x"]} { set s [string range $s 2 end] }
    scan $s %x v
    return $v
}

proc smx_rd {m off n} {
    global SMX_BASE
    return [master_read_32 $m [expr {$SMX_BASE + $off}] $n]
}

proc smx_wr {m off vals} {
    global SMX_BASE
    master_write_32 $m [expr {$SMX_BASE + $off}] $vals
}

# unpack a list of 32-bit hex words into a list of byte values, element 0 = lowest byte of word 0
proc words_to_bytes {words} {
    set out {}
    foreach w $words {
        set h [string tolower $w]
        if {[string equal [string range $h 0 1] "0x"]} { set h [string range $h 2 end] }
        set h [string range "00000000$h" end-7 end]
        foreach p {6 4 2 0} {
            scan [string range $h $p [expr {$p + 1}]] %x b
            lappend out $b
        }
    }
    return $out
}

# run one case, return 1 if it passed
proc run_case {m case P} {
    global SMX_CTRL SMX_STATUS SMX_LEN SMX_ROWS SMX_K SMX_CYCLES SMX_XBUF SMX_YBUF
    global SMX_ROWSTEP SMX_ROW_OVERHEAD SMX_POLL_MAX
    set name [lindex $case 0]
    set L    [lindex $case 1]
    set R    [lindex $case 2]
    set K    [lindex $case 3]
    set xrows [lindex $case 4]
    set yrows [lindex $case 5]
    set ok 1

    smx_wr $m $SMX_K    $K
    smx_wr $m $SMX_LEN  $L
    smx_wr $m $SMX_ROWS $R
    for {set r 0} {$r < $R} {incr r} {
        smx_wr $m [expr {$SMX_XBUF + $r * $SMX_ROWSTEP}] [lindex $xrows $r]
    }
    smx_wr $m $SMX_CTRL 1

    set done 0
    for {set i 0} {$i < $SMX_POLL_MAX} {incr i} {
        set st [hex2int [lindex [smx_rd $m $SMX_STATUS 1] 0]]
        if {($st & 2) != 0} { set done 1 ; break }
    }
    if {!$done} {
        puts "  \[FAIL\] $name: DONE never set (STATUS = $st)"
        return 0
    }
    if {($st & 4) != 0} {
        puts "  \[FAIL\] $name: ERR set (STATUS = $st) for L = $L, R = $R"
        return 0
    }
    if {($st & 1) != 0} {
        puts "  \[FAIL\] $name: BUSY and DONE both set (STATUS = $st)"
        set ok 0
    }

    set cyc [hex2int [lindex [smx_rd $m $SMX_CYCLES 1] 0]]
    set G [expr {($L + $P - 1) / $P}]
    set want [expr {$R * (2 * $G + $SMX_ROW_OVERHEAD) + 1}]
    set cyc_ok [expr {$cyc == $want}]
    if {!$cyc_ok} { set ok 0 }

    set bad 0
    set first_bad ""
    set nw [expr {($L + 3) / 4}]
    for {set r 0} {$r < $R} {incr r} {
        set got  [words_to_bytes [smx_rd $m [expr {$SMX_YBUF + $r * $SMX_ROWSTEP}] $nw]]
        set exp  [lindex $yrows $r]
        for {set i 0} {$i < $L} {incr i} {
            if {[lindex $got $i] != [lindex $exp $i]} {
                incr bad
                if {[string length $first_bad] == 0} {
                    set first_bad "row $r elem $i: got [lindex $got $i], want [lindex $exp $i]"
                }
            }
        }
    }
    if {$bad > 0} { set ok 0 }

    set tag [expr {$ok ? "PASS" : "FAIL"}]
    puts [format "  \[%s\] %-24s L=%-3d R=%-2d K=%-5d  cycles=%d (want %d)  mismatches=%d" \
            $tag $name $L $R $K $cyc $want $bad]
    if {$bad > 0} { puts "         first mismatch: $first_bad" }
    return $ok
}

# START with an invalid LEN must set DONE+ERR without ever raising BUSY
proc run_err_test {m} {
    global SMX_CTRL SMX_STATUS SMX_LEN SMX_ROWS SMX_CYCLES
    smx_wr $m $SMX_LEN 0
    smx_wr $m $SMX_ROWS 1
    smx_wr $m $SMX_CTRL 1
    set st [hex2int [lindex [smx_rd $m $SMX_STATUS 1] 0]]
    set cyc [hex2int [lindex [smx_rd $m $SMX_CYCLES 1] 0]]
    set ok [expr {$st == 6 && $cyc == 0}]
    puts [format "  \[%s\] %-24s LEN=0 -> STATUS=%d (want 6 = DONE+ERR), CYCLE_CNT=%d (want 0)" \
            [expr {$ok ? "PASS" : "FAIL"}] "invalid_config_ERR" $st $cyc]
    return $ok
}

proc smx_run_all {m} {
    global SMX_HWPARAM SMX_CASES SMX_DATA_P SMX_DATA_N_SEG
    set hw [hex2int [lindex [smx_rd $m $SMX_HWPARAM 1] 0]]
    set P       [expr {$hw & 0xFF}]
    set log2L   [expr {($hw >> 8) & 0xF}]
    set rmax    [expr {($hw >> 12) & 0xFF}]
    set log2N   [expr {($hw >> 20) & 0xF}]
    set version [expr {($hw >> 24) & 0xFF}]
    puts [format "HW_PARAM = 0x%08X : P = %d, L_MAX = %d, R_MAX = %d, N_SEG = %d, VERSION = 0x%02X" \
            $hw $P [expr {1 << $log2L}] $rmax [expr {1 << $log2N}] $version]
    set all 1
    if {$version != 0x10} { puts "  \[FAIL\] VERSION is not 0x10: wrong bitstream or wrong base address?" ; set all 0 }
    if {$P != $SMX_DATA_P || [expr {1 << $log2N}] != $SMX_DATA_N_SEG} {
        puts "  \[FAIL\] test data was generated for P = $SMX_DATA_P, N_SEG = $SMX_DATA_N_SEG; regenerate with gen_test_data.py"
        set all 0
    }
    if {!$all} { return 0 }

    set n 0 ; set npass 0
    foreach c $SMX_CASES {
        incr n
        if {[run_case $m $c $P]} { incr npass }
    }
    incr n
    if {[run_err_test $m]} { incr npass }
    puts "$npass / $n tests passed"
    return [expr {$npass == $n}]
}

# ---- main: skipped when a mock is loaded (SMX_MOCK) so the logic can be tested without a board ----
set here [file dirname [file normalize [info script]]]
source [file join $here smx_test_data.tcl]

if {![info exists SMX_MOCK]} {
    set paths [get_service_paths master]
    if {[llength $paths] == 0} {
        puts "No JTAG master found. Is the board powered, the USB-Blaster II connected and smx_de10.sof programmed?"
        puts "SMX_DEMO_RESULT: FAIL"
        return
    }
    set m [lindex $paths 0]
    puts "Using master: $m"
    open_service master $m
    set res [smx_run_all $m]
    close_service master $m
    puts [expr {$res ? "SMX_DEMO_RESULT: PASS" : "SMX_DEMO_RESULT: FAIL"}]
}
