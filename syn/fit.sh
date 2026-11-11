#!/usr/bin/env bash
# fit.sh - full Quartus compile of smx_core alone, for resource and Fmax numbers.
# Ports are virtual pins, since the IP connects to fabric, not to device pins. The SDC has only the
# clock, so these numbers are register-to-register: acc_* and rst_n paths are not timed.
# Files come from scripts/rtl.f. Each run gets a git-ignored syn/fit/p<P>_n<N_SEG>_s<SEED>/.
#
# Usage: syn/fit.sh [P] [N_SEG] [SEED]        (default: 8 8 1)
# Needs: quartus_sh (Quartus Prime Lite 18.1) on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

p="${1:-8}"; n="${2:-8}"; seed="${3:-1}"
dir="syn/fit/p${p}_n${n}_s${seed}"
rm -rf "${dir}" && mkdir -p "${dir}"
{
  echo 'set_global_assignment -name FAMILY "Cyclone V"'
  echo 'set_global_assignment -name DEVICE 5CSXFC6D6F31C6'
  echo 'set_global_assignment -name TOP_LEVEL_ENTITY smx_core'
  echo 'set_global_assignment -name NUM_PARALLEL_PROCESSORS 4'
  echo "set_global_assignment -name SEED ${seed}"
  echo 'set_global_assignment -name SDC_FILE smx.sdc'
  grep -v '^#' scripts/rtl.f | sed "s|^\.\./|$(pwd)/|; s|^|set_global_assignment -name SYSTEMVERILOG_FILE |"
  echo "set_parameter -name P ${p}"
  echo "set_parameter -name N_SEG ${n}"
  for port in rst_n acc_addr[*] acc_write acc_writedata[*] acc_byteenable[*] acc_read \
              acc_readdata[*] status_busy status_done status_err; do
    echo "set_instance_assignment -name VIRTUAL_PIN ON -to ${port}"
  done
} > "${dir}/smx_core.qsf"
cat > "${dir}/smx.sdc" <<'SDC'
create_clock -name clk -period 10.000 [get_ports clk]
derive_clock_uncertainty
SDC

(cd "${dir}" && quartus_sh --flow compile smx_core > flow.out 2>&1) || { tail -20 "${dir}/flow.out"; exit 1; }

echo "== P=${p} N_SEG=${n} SEED=${seed}, Fitter"
grep -E '^; (Logic utilization \(in ALMs\)|Total registers|Total block memory bits|Total RAM Blocks|Total DSP Blocks)' "${dir}/smx_core.fit.rpt" | sort -u
grep -E '^; Combinational ALUT usage for logic' "${dir}/smx_core.fit.rpt" | head -1
# Slow model at both temperatures: on this device the 0C corner is usually the worse one.
for corner in 85C 0C; do
  echo "== TimeQuest, slow 1100mV ${corner}"
  for t in 'Fmax' 'Setup' 'Hold'; do
    grep -A5 -E "^; Slow 1100mV ${corner} Model ${t} Summary" "${dir}/smx_core.sta.rpt" | grep -E '^; [0-9]|^; clk'
  done
done
