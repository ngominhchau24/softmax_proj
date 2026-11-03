#!/usr/bin/env bash
# map_check.sh - Quartus Analysis & Synthesis smoke check of one rtl/core block,
# swept over a parameter. Throwaway projects go to syn/map_check/ (git-ignored).
# This is not the IP synthesis run; resource and Fmax numbers come from syn/smx.qpf.
#
# Usage: syn/map_check.sh <module> [PARAM=v1,v2,...]
#   e.g. syn/map_check.sh smx_exp2 N_SEG=4,8,16
#        DEPS="smx_exp2 smx_scale" syn/map_check.sh smx_core P=8     (sub-blocks)
# A parameter the module does not have is silently ignored by Quartus.
# Needs: quartus_map (Quartus Prime Lite 18.1) on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

top="$1"
sweep="${2:-}"
pname="${sweep%%=*}"
values="${sweep#*=}"
[ -z "${sweep}" ] && { pname=""; values="default"; }

fail=0
for v in ${values//,/ }; do
  dir="syn/map_check/${top}_${pname:-p}${v}"
  rm -rf "${dir}" && mkdir -p "${dir}"
  {
    echo 'set_global_assignment -name FAMILY "Cyclone V"'
    echo 'set_global_assignment -name DEVICE 5CSXFC6D6F31C6'
    echo "set_global_assignment -name TOP_LEVEL_ENTITY ${top}"
    echo 'set_global_assignment -name NUM_PARALLEL_PROCESSORS 2'
    echo "set_global_assignment -name SYSTEMVERILOG_FILE $(pwd)/rtl/pkg/smx_pkg.sv"
    for d in ${DEPS:-}; do echo "set_global_assignment -name SYSTEMVERILOG_FILE $(pwd)/rtl/core/${d}.sv"; done
    echo "set_global_assignment -name SYSTEMVERILOG_FILE $(pwd)/rtl/core/${top}.sv"
    if [ -n "${pname}" ]; then echo "set_parameter -name ${pname} ${v}"; fi
  } > "${dir}/${top}.qsf"
  if (cd "${dir}" && quartus_map "${top}" > map.out 2>&1); then
    res="OK  "
  else
    res="FAIL"; fail=1
  fi
  echo "${res} ${top} ${pname:+${pname}=}${v}: $(grep -E 'Analysis & Synthesis was' "${dir}/map.out" | sed 's/^Info: //')"
  grep -E '^Error' "${dir}/map.out" | head -5 || true
  grep -E '^; (Total registers|Total DSP Blocks|Total block memory bits|Combinational ALUT usage for logic) ' "${dir}/${top}.map.rpt" 2>/dev/null | head -4 || true
done
exit "${fail}"
