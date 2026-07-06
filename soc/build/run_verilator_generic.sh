#!/usr/bin/env bash
set -euo pipefail

# Capture and normalize paths before changing directory so relative paths are
# resolved against the caller's working directory.
workdir="$1"
wrapper="$2"
workdir_abs=$(realpath "$workdir")
wrapper_abs=$(realpath "$wrapper")
TOPNAME=$(basename "$wrapper" .v)

cd "$(dirname "$0")/.."

PERL=${PERL:-/c/Strawberry/perl/bin/perl.exe}
VERILATOR=${VERILATOR:-/c/App/verilator-install/bin/verilator}
GPP=${GPP:-/c/msys64/mingw64/bin/g++.exe}

export TMP=$(cygpath -m "$TMP")
export TEMP=$(cygpath -m "$TEMP")
export TMPDIR=$(cygpath -m "${TMPDIR:-$TMP}")

OBJ="$workdir_abs/obj_dir"

# Windows-native paths for the Verilator binary; MinGW make accepts POSIX paths.
WIN_WRAPPER=$(cygpath -w "$wrapper_abs")
WIN_OBJ=$(cygpath -w "$OBJ")

rm -rf "$OBJ"

"$PERL" "$VERILATOR" --main --timing +incdir+rtl/core \
    --top-module "$TOPNAME" \
    "$WIN_WRAPPER" -f build/generic_files.f -Wno-fatal -Mdir "$WIN_OBJ"

# Verilator 5.x's default make target builds archives. Compile and then link
# the executable manually.
mingw32-make -C "$OBJ" -f "V${TOPNAME}.mk" \
    CFG_CXXFLAGS_PCH_I=-include CFG_CXXFLAGS_COROUTINES=-fcoroutines

"$GPP" -std=c++20 -fcoroutines -DVL_TIME_CONTEXT \
    -I"$OBJ" -IC:/App/verilator-install/include \
    "$(cygpath -w "$OBJ/V${TOPNAME}__ALL.a")" \
    "$(cygpath -w "$OBJ/libverilated.a")" \
    -o "$(cygpath -w "$OBJ/V${TOPNAME}.exe")" -lpthread

"$OBJ/V${TOPNAME}.exe" "${@:3}"
