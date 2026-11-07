#!/usr/bin/env bash
# build.sh - build the DE10-Standard demo: Platform Designer system -> Quartus compile -> .sof.
# Output: syn/de10/output_files/de10.sof (copy to syn/release/ to track it in git).
# Needs: Quartus Prime Lite 18.1; set QUARTUS_ROOT if it is not C:/intelFPGA_lite/18.1/hoho.
set -euo pipefail
cd "$(dirname "$0")"

q="${QUARTUS_ROOT:-/c/intelFPGA_lite/18.1/hoho}"
export PATH="$q/quartus/bin64:$q/quartus/sopc_builder/bin:$PATH"

rm -rf smx_system smx_system.qsys
ipdir="$(cygpath -m "$(pwd)/../../ip" 2>/dev/null || echo "$(pwd)/../../ip")"
qsys-script --script=make_system.tcl --search-path="${ipdir}/*,\$" > qsys_script.log 2>&1 || { tail -20 qsys_script.log; exit 1; }
qsys-generate smx_system.qsys --synthesis=VERILOG --output-directory=smx_system \
  --search-path="${ipdir}/*,\$" \
  --family="Cyclone V" --part=5CSXFC6D6F31C6 > qsys_generate.log 2>&1 || { tail -20 qsys_generate.log; exit 1; }

quartus_sh --flow compile de10 > compile.log 2>&1 || { tail -20 compile.log; exit 1; }
ls -la output_files/de10.sof
grep -E '^(Logic utilization|Total registers|Total pins|Total block memory bits|Total DSP Blocks)' output_files/de10.fit.summary
