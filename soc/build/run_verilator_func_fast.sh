#!/usr/bin/env bash
# Run the fast functional test in Verilator on MSYS2/Windows.
# This script encodes the workarounds needed for this workspace:
#   - Strawberry Perl is used because MSYS2 Perl may lack Pod::Usage.
#   - MinGW GCC 15 needs -fcoroutines for <coroutine>.
#   - Verilator's installed verilated.mk leaves CFG_CXXFLAGS_PCH_I empty, so
#     we force -include on the make command line.
#   - TMP/TEMP/TMPDIR are normalised to forward slashes so MSYS2 path
#     conversion does not break MinGW GCC temporary-file creation.
set -euo pipefail
cd "$(dirname "$0")/.."

PERL=${PERL:-/c/Strawberry/perl/bin/perl.exe}
VERILATOR=${VERILATOR:-/c/App/verilator-install/bin/verilator}

# Normalise temp paths to mixed (forward-slash) Windows paths.
export TMP=$(cygpath -m "$TMP")
export TEMP=$(cygpath -m "$TEMP")
export TMPDIR=$(cygpath -m "${TMPDIR:-$TMP}")

echo "== Verilate tb_func_fast =="
rm -rf obj_dir_func_fast
"$PERL" "$VERILATOR" --main --timing +incdir+rtl/core \
  -f build/func_fast_files.f -Wno-fatal -Mdir obj_dir_func_fast

echo "== Compile Verilated C++ =="
mingw32-make -C obj_dir_func_fast -f Vtb_func_fast.mk \
  CFG_CXXFLAGS_PCH_I=-include CFG_CXXFLAGS_COROUTINES=-fcoroutines

echo "== Run simulation =="
./obj_dir_func_fast/Vtb_func_fast.exe
