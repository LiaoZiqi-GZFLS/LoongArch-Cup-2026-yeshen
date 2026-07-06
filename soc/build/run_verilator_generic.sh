#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PERL=${PERL:-/c/Strawberry/perl/bin/perl.exe}
VERILATOR=${VERILATOR:-/c/App/verilator-install/bin/verilator}

export TMP=$(cygpath -m "$TMP")
export TEMP=$(cygpath -m "$TEMP")
export TMPDIR=$(cygpath -m "${TMPDIR:-$TMP}")

workdir="$1"
wrapper="$2"
TOPNAME=$(basename "$wrapper" .v)
OBJ="$workdir/obj_dir"

rm -rf "$OBJ"

"$PERL" "$VERILATOR" --main --timing +incdir+rtl/core \
    "$wrapper" -f build/generic_files.f -Wno-fatal -Mdir "$OBJ"

mingw32-make -C "$OBJ" -f "V${TOPNAME}.mk" \
    CFG_CXXFLAGS_PCH_I=-include CFG_CXXFLAGS_COROUTINES=-fcoroutines

"$OBJ/V${TOPNAME}.exe" "${@:3}"
