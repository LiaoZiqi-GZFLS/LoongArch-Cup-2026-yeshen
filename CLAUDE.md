# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a **2026 龙芯杯 (LoongArch Cup) team-contest preliminary-round** workspace. The goal is to build a bare-metal LoongArch32-Reduced (LA32R) SoC that runs the committee's functional and performance test programs on FPGA. Scoring = functional score (per-instruction correctness vs. a reference CPU) + performance score (fewer cycles is better, measured by an on-chip cycle counter).

The repository currently contains:
- `Description.md` — the full official contest requirements and hard constraints (Chinese). **Read this before making design decisions.**
- `open-la500-master/` — the **openLA500 (齐物)** processor core, a third-party open-source LA32R core (single-issue 5-stage pipeline) used as the starting base.
- `soc/` — the integrated SoC: RTL under `soc/rtl/core/`, testbenches under `soc/sim/`, file lists and scripts under `soc/build/`, and build/utility scripts under `soc/scripts/`.
- `cpu_project/` — the Vivado 2023.2 project (`cpu_project/cpu_project.xpr`) used for synthesis and implementation.
- `chiplab/` — the ChipLab regression environment (subtree or submodule) used for committee functional and performance tests.
- `docs/` — design reports and documentation.

Key files checked in: `cpu_project/cpu_project.xpr`, `soc/scripts/build.tcl`, and `soc/sim/tb_soc_generic.v`.

## Hard contest constraints (from `Description.md`)

These shape every architectural choice — violating them loses points or disqualifies:
- **ISA**: LA32R *reduced* base subset only. **No floating-point. No TLB/MMU virtual-memory privileged instructions.** Note: the openLA500 base *does* implement a 32-entry TLB and MMU — this is the main mismatch to reconcile (the contest target is a DA/direct-address bare-metal system, not paged virtual memory).
- **Memory**: FPGA on-chip BRAM only (no external DDR/Flash). IMEM ≥ 8KB, DMEM ≥ 8KB.
- **Required peripherals**: on-chip cycle counter (performance scoring basis), 8× seven-segment displays, and working CPU↔IO interconnect.
- **Platform**: Xilinx Artix-7 **XC7A200T**, Vivado **2023.2**, official LA32R cross-compile toolchain, AMBA bus IP provided by the committee.
- Address-space layout (memory + IO) must match the 《龙芯架构32位精简版参考手册》.
- Any third-party code/IP (including openLA500) **must be cited in the design report** — academic-integrity requirement.

## openLA500 core architecture

The core is a classic single-issue **static 5-stage pipeline**. Stage modules and their files:

| Stage | File | Role |
|-------|------|------|
| pre-fetch / fetch | `if_stage.v` | maintains `nextpc`, issues fetch to icache/tlb/btb; `fs` is the first true pipeline register |
| decode | `id_stage.v` | decode → opcode + reg numbers; reads `regfile`/`csr`; forwarding + stall control; branch-misprediction correction via `br_bus` |
| execute | `exe_stage.v` | drives `alu` (simple ops), `mul` (Wallace-tree, 2 stages), `div` (iterative, ~34 cycles); computes load/store address |
| memory | `mem_stage.v` | waits on dcache; selects final result |
| writeback | `wb_stage.v` | writes back to `regfile`/`csr`; handles exceptions, pipeline flush, redirect to exception entry |

Top level and supporting modules:
- `mycpu_top.v` — **top module `core_top`**; wires all stages, caches, tlb, csr, axi_bridge together. External interface is **AXI3** (read/write channels) plus a debug port. This is the synthesis top.
- `lacc_core.v` (module `core_top`'s neighbor) — top of the optional LaCC coprocessor; wraps `lacc_demo.v`.
- `icache.v` / `dcache.v` — 2-way set-associative caches; random (LFSR) replacement. dcache adds dirty-bit + write-buffer state machine. The behavioral `data_bank_sram`/`tagv_sram` models are defined in `soc/rtl/core/dcache.v` at the bottom, guarded by `` `ifdef SIMU `` (see macros below).
- `tlb_entry.v` / `addr_trans.v` — 32-entry fully-associative TLB (CAM), shared by I/D with two query ports; virtual→physical translation.
- `csr.v` / `csr.h` — control/status registers; `csr.h` holds all CSR bit-field and exception-code (`ECODE_*`) macros.
- `btb.v` — branch prediction: 32-entry BTB (CAM) + 8-entry RAS. Correct prediction removes the fetch bubble; misprediction is corrected in `ds`.
- `alu.v`, `mul.v`, `div.v` — datapath compute units.
- `regfile.v`, `perf_counter.v`, `axi_bridge.v` (cache-miss → AXI3), `tools.v` (generic encoders/decoders/priority-select helpers).
- `mycpu.h` — bus-width macros for inter-stage buses and the feature macros below.

Pipeline handshake protocol (see `doc/设计概述.md`): every stage uses `stage_valid` / `stage_ready_go` / `stage_allowin` / `stage_to_nextstage_valid`. A stall propagates backward by deasserting `allowin`. When changing pipeline timing, preserve this contract.

## Compile-time macros (in `soc/rtl/core/mycpu.h`)

- **`` `define SIMU ``** — permanently defined in `soc/rtl/core/mycpu.h`. It selects the **behavioral SRAM models** (defined inside `dcache.v`) for simulation. In synthesis Vivado infers the reg-array templates as Block RAM, so the Xilinx SRAM IP (`IP/data_bank_sram.xcix` / `tagv_sram.xcix`) is optional. The Vivado `xsim` script passes `-d SIMU` explicitly; the Verilator generic harness relies on the `define` in `mycpu.h`.
- **`` `define HAS_LACC ``** — the only optional macro. It enables the **LaCC** (LoongArch32R Custom Coprocessor Interface), a hook for adding custom instructions (opcode `1100`). Touching it changes inter-stage bus widths (`DS_TO_ES_BUS_WD` grows) and adds `` `ifdef HAS_LACC `` paths through `id_stage.v`/`exe_stage.v`/`mycpu_top.v`. Interface and how-to-add-an-instruction are in `doc/lacc接口.md`. Leave off unless intentionally extending the ISA.

## Non-FPGA simulation flows

Run from the `soc/` directory.

### Verilator functional test (`tb_soc_generic`)

Use the captured script:

```bash
bash build/run_verilator_generic.sh
```

Manual equivalent (MSYS2/Windows, Verilator 5.x):

```bash
export TMP=$(cygpath -m "$TMP")
export TEMP=$(cygpath -m "$TEMP")
export TMPDIR=$(cygpath -m "${TMPDIR:-$TMP}")
/c/Strawberry/perl/bin/perl.exe /c/App/verilator-install/bin/verilator \
  --main --timing +incdir+rtl/core -f build/generic_files.f -Wno-fatal -Mdir obj_dir_generic
mingw32-make -C obj_dir_generic -f Vtb_soc_generic.mk \
  CFG_CXXFLAGS_PCH_I=-include CFG_CXXFLAGS_COROUTINES=-fcoroutines
./obj_dir_generic/Vtb_soc_generic.exe
```

Expected result: `PASS tb_soc_generic` with `num_data=0x3a00003a`, `led_rg0=01`, `led_rg1=01`.

### Vivado behavioral simulation (`xsim`)

```bash
bash build/xsim_func_fast.sh
```

Expected result: `PASS tb_func_fast` at around 5.3 ms.

Note: the openLA500 RTL contains many registers without reset values. Vivado xsim is a 4-state simulator and previously failed to boot because the cache tag/data SRAM output buffers were uninitialized (`X`), making the cache-hit signal `X` and stalling the pipeline. The behavioral SRAM models in `dcache.v` now have `initial` blocks that zero the arrays and output buffers when `SIMU` is defined. This does not affect Verilator (2-state, already defaults to 0) or synthesis (the `SIMU` guard).

## ChipLab regression commands

All commands are run from the `soc/` directory.

```bash
make run-func       # build + run nscscc_func (Verilator)
make run-perf       # build + run all 20 performance benchmarks
make run-all        # build + run functional + performance tests
make summary        # one-line status from the latest JSON report
```

To run under Vivado xsim:

```bash
python scripts/run_tests.py -t nscscc_func -s xsim
```

To build images without running:

```bash
make build          # all tests
make build-func     # only nscscc_func
make build-perf     # all 20 performance benchmarks
make clean-mem      # remove generated .mem files
make clean-reports  # remove generated reports
make clean          # remove .mem files and reports
python scripts/build_tests.py -t bitcount coremark
```

Reports are written to `soc/sw/tests/reports/run-<timestamp>.json`.

## Documentation

The design report and RTL source are the best sources for design intent:
- `docs/design_report.md` — overview (single-issue 5-stage, 2-way caches, 32-entry TLB, BTB+RAS, AXI3, ~50MHz on FPGA, taped out on SMIC 180nm).
- `soc/rtl/core/*.v` — detailed per-stage walkthrough and the pipeline handshake protocol.
- `soc/rtl/core/btb.v` — BTB/RAS design.
- `doc/lacc接口.md` — LaCC coprocessor interface spec.

## Working notes

- RTL is Verilog-2001 style; module names sometimes differ from filenames (e.g. `mul.v` defines `YDecoder`/`BoothBase`/`WallaceTreeBase`/`mul`; `tools.v` defines several small modules). Use `grep -n "^module"` to locate a module rather than assuming file = module.
- The base core targets AXI3 + TLB/MMU; the contest target is a simpler BRAM-backed, no-MMU SoC. Expect to strip/bypass MMU paths and bridge AXI to the committee's AMBA/BRAM peripherals rather than use external memory.
