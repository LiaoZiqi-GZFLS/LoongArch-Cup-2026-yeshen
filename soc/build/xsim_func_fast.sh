#!/usr/bin/env bash
# Standalone xvlog/xelab/xsim flow for tb_func_fast (no Vivado project)
cd "$(dirname "$0")/.."
rm -rf xsim.dir/xsim_func_fast xsim.dir/work
mkdir -p xsim.dir/xsim_func_fast

xvlog -sv -d SIMU \
  rtl/core/*.v rtl/soc/*.v rtl/periph/*.v \
  sim/tb_soc_generic.v sim/tb_func_fast.v \
  -i rtl/core \
  2>&1 | tee build/xvlog_func_fast.log

xelab -L xsim.dir/work \
  tb_func_fast -s xsim_func_fast \
  2>&1 | tee build/xelab_func_fast.log

xsim xsim_func_fast -runall \
  2>&1 | tee build/xsim_func_fast.log
