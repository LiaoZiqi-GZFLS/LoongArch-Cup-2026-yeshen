#!/usr/bin/env bash
# Standalone xvlog/xelab/xsim flow using dual-issue RTL from chiplab/IP/myCPU
# with the simplified soc_top/axi_mem_soc wrappers (128-bit AXI NOT required).
#
# NOTE: The icache is patched to use 32-bit word refills so the simplified
# axi_mem_soc (which only returns [31:0]) can feed the dual-issue pipeline.
set -euo pipefail
cd "$(dirname "$0")/.."

CHIPLAB=../chiplab
MYCPU=$CHIPLAB/IP/myCPU
SOC=rtl/soc
PERIPH=rtl/periph
SIM=sim

# Clean
rm -rf xsim.dir/dualie_func xsim.dir/work_dualie
mkdir -p xsim.dir/dualie_func

echo "=== xvlog (dual-issue) ==="
xvlog -sv -d SIMU \
  ${MYCPU}/addr_trans.v \
  ${MYCPU}/alu.v \
  ${MYCPU}/axi_bridge.v \
  ${MYCPU}/btb.v \
  ${MYCPU}/cdc_sched_bridge.v \
  ${MYCPU}/csr.v \
  ${MYCPU}/dcache.v \
  ${MYCPU}/div.v \
  ${MYCPU}/exe_stage.v \
  ${MYCPU}/exe1_stage.v \
  ${MYCPU}/icache.v \
  ${MYCPU}/id_stage.v \
  ${MYCPU}/if_stage.v \
  ${MYCPU}/lacc_core.v \
  ${MYCPU}/lacc_demo.v \
  ${MYCPU}/mem_stage.v \
  ${MYCPU}/mem1_stage.v \
  ${MYCPU}/mul.v \
  ${MYCPU}/mycpu_top.v \
  ${MYCPU}/perf_counter.v \
  ${MYCPU}/predecode_stage.v \
  ${MYCPU}/regfile.v \
  ${MYCPU}/sched_cache.v \
  ${MYCPU}/sched_scoreboard.v \
  ${MYCPU}/tlb_entry.v \
  ${MYCPU}/tools.v \
  ${MYCPU}/wb_stage.v \
  ${MYCPU}/wb1_stage.v \
  ${SOC}/axi_decoder_1x2.v \
  ${SOC}/axi_mem_soc.v \
  ${SOC}/soc_top.v \
  ${PERIPH}/confreg.v \
  ${PERIPH}/counter.v \
  ${PERIPH}/seg7.v \
  ${SIM}/tb_soc_generic.v \
  ${SIM}/tb_func_fast.v \
  -i ${MYCPU} \
  -i rtl/core \
  2>&1 | tail -5

echo "=== xelab ==="
xelab -L xsim.dir/work_dualie \
  tb_func_fast -s dualie_func \
  2>&1 | tail -5

echo "=== xsim (func test) ==="
xsim dualie_func -runall \
  2>&1 | tail -20
