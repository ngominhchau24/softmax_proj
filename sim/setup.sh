# setup.sh - point the sim/ flow at ModelSim. Source it once per terminal, do not execute it:
#
#   source sim/setup.sh                      (from the repo root)
#   source setup.sh                          (from sim/)
#
# It sets vlib, vmap, vlog and vsim, the variables sim/Makefile reads.
# The ModelSim folder (the one that holds vsim or vsim.exe) is taken from, in this order:
#   1. MODELSIM_DIR, if you set it:  MODELSIM_DIR=/mnt/d/intelFPGA_lite/18.1/modelsim_ase/win32aloem source sim/setup.sh
#   2. the usual Intel install folders on drives C and D (WSL) or under /opt and $HOME (Linux)
#   3. vsim already on PATH
# To make it permanent for your machine, add the MODELSIM_DIR line to ~/.bashrc.

_smx_dir="${MODELSIM_DIR:-}"

if [ -z "$_smx_dir" ]; then
  for _smx_d in \
      /mnt/[cd]/intelFPGA_lite/*/modelsim_ase/win32aloem \
      /mnt/[cd]/intelFPGA/*/modelsim_ase/win32aloem \
      /mnt/[cd]/intelFPGA_pro/*/modelsim_ase/win32aloem \
      /mnt/[cd]/intelFPGA*/*/modelsim_ae/win32aloem \
      /opt/intelFPGA*/*/modelsim_ase/bin \
      "$HOME"/intelFPGA*/*/modelsim_ase/bin; do
    if [ -e "$_smx_d/vsim.exe" ] || [ -e "$_smx_d/vsim" ]; then
      _smx_dir="$_smx_d"
      break
    fi
  done
fi

if [ -n "$_smx_dir" ] && [ -e "$_smx_dir/vsim.exe" ]; then
  _smx_ext=".exe"                            # Windows ModelSim called from WSL
elif [ -n "$_smx_dir" ] && [ -e "$_smx_dir/vsim" ]; then
  _smx_ext=""
elif [ -n "$_smx_dir" ]; then
  echo "setup.sh: no vsim or vsim.exe in $_smx_dir"
  _smx_dir=""
fi

if [ -n "$_smx_dir" ]; then
  export vlib="$_smx_dir/vlib$_smx_ext"
  export vmap="$_smx_dir/vmap$_smx_ext"
  export vlog="$_smx_dir/vlog$_smx_ext"
  export vsim="$_smx_dir/vsim$_smx_ext"
  echo "setup.sh: ModelSim in $_smx_dir"
  "$vsim" -version
elif command -v vsim >/dev/null 2>&1; then
  unset vlib vmap vlog vsim                  # Makefile defaults: the tools on PATH
  echo "setup.sh: using vsim on PATH: $(command -v vsim)"
  vsim -version
else
  echo "setup.sh: ModelSim not found."
  echo "  Find the folder that holds vsim.exe in Windows Explorer, then run for example:"
  echo "  MODELSIM_DIR=/mnt/c/intelFPGA_lite/18.1/modelsim_ase/win32aloem source sim/setup.sh"
fi

command -v make >/dev/null 2>&1    || echo "setup.sh: make is missing:  sudo apt install -y make"
python3 -c "import numpy" 2>/dev/null || echo "setup.sh: python3 with numpy is missing:  sudo apt install -y python3-numpy"

unset _smx_dir _smx_d _smx_ext
