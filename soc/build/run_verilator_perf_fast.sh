#!/usr/bin/env bash
# Run the fast performance test in Verilator on MSYS2/Windows.
set -euo pipefail
cd "$(dirname "$0")/.."

PERL=${PERL:-/c/Strawberry/perl/bin/perl.exe}
VERILATOR=${VERILATOR:-/c/App/verilator-install/bin/verilator}

export TMP=$(cygpath -m "$TMP")
export TEMP=$(cygpath -m "$TEMP")
export TMPDIR=$(cygpath -m "${TMPDIR:-$TMP}")

echo "== Verilate tb_perf_fast =="
rm -rf obj_dir_perf_fast_now
"$PERL" "$VERILATOR" --main --timing +incdir+rtl/core \
  -f build/perf_fast_files.f -Wno-fatal -Mdir obj_dir_perf_fast_now

echo "== Compile Verilated C++ =="
mingw32-make -C obj_dir_perf_fast_now -f Vtb_perf_fast.mk \
  CFG_CXXFLAGS_PCH_I=-include CFG_CXXFLAGS_COROUTINES=-fcoroutines

echo "== Link executable =="
/c/msys64/mingw64/bin/g++.exe -std=c++20 -fcoroutines -O2 -DVL_TIME_CONTEXT \
  -Iobj_dir_perf_fast_now -IC:/App/verilator-install/include \
  obj_dir_perf_fast_now/Vtb_perf_fast__ALL.a obj_dir_perf_fast_now/libverilated.a \
  -o obj_dir_perf_fast_now/Vtb_perf_fast.exe -lpthread

echo "== Run simulation =="
./obj_dir_perf_fast_now/Vtb_perf_fast.exe
