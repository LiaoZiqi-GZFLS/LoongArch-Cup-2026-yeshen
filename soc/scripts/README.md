# ChipLab Test Integration

This directory contains the automation for building and running the official
chiplab `nscscc_func` and `nscscc_perf` test suites against the LoongArch-Cup SoC.

## Quick start

```bash
cd soc
make run-all
```

This builds every test image, runs them under Verilator, and writes a JSON
report to `soc/sw/tests/reports/run-<timestamp>.json`.

## Requirements

- Python 3 with `PyYAML`
- LA32R cross toolchain (`loongarch32r-linux-gnusf-*`)
- Verilator (Windows MSYS2 path `C:/App/verilator-install`) or Vivado 2023.2
- GNU Make

Install Python dependency:

```bash
pip install pyyaml
```

## Build commands

```bash
make build          # build all tests
make build-func     # build only nscscc_func
make build-perf     # build all 20 performance benchmarks
make clean-mem      # remove generated .mem files
```

## Run commands

```bash
make run-func       # build + run nscscc_func
make run-perf       # build + run all performance tests
make run-all        # build + run everything
make summary        # print CI status from the latest report
```

Use the runner directly for finer control:

```bash
python scripts/run_tests.py -c performance -t bitcount coremark -s verilator
python scripts/run_tests.py -c all -s xsim
```

## Pass/fail criteria

- **Functional:** `num_data == 0x3a00003a` and `led_rg0 == led_rg1 == 01`.
- **Performance:** `num_data` becomes non-zero and stable for `stable_cycles`.
- **Timeout:** if neither condition is met within `timeout_cycles`, the test is
  marked `TIMEOUT`.

## Performance hang note

The chiplab performance startup reads `CPUCFG_1` to detect caches. The SoC now
reports `CPUCFG_1 = 0` so the startup skips `cacop`-based cache invalidation
loops that hung at PC ~`0x1c000188`. This is an integration-level workaround,
not a CPU microarchitecture fix.

## Vivado synthesis

The synthesis flow remains unchanged:

```bash
vivado -mode batch -source soc/scripts/build.tcl -tclargs synth
vivado -mode batch -source soc/scripts/build.tcl -tclargs bit
```

An optional fourth argument preloads a specific `.mem` into the bitstream BRAM:

```bash
vivado -mode batch -source soc/scripts/build.tcl -tclargs bit \
  "$(pwd)/soc/sw/tests/perf_coremark.mem"
```
