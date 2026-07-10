#!/usr/bin/env bash
# Backward-compatible fast functional test driver.
# It now delegates to the generic Verilator harness, with tb_func_fast.v as
# the top wrapper around tb_soc_generic.
set -euo pipefail
cd "$(dirname "$0")/.."

exec bash build/run_verilator_generic.sh . sim/tb_func_fast.v

