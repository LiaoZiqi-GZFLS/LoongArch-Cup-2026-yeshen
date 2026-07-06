# soc/Makefile -- top-level convenience wrapper for chiplab test integration.
SOC := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(realpath $(SOC)/..)
PYTHON ?= python

.PHONY: help build build-func build-perf run-func run-perf run-all clean-mem report summary clean-reports clean

help:
	@echo "Targets:"
	@echo "  make build        - build all test .mem images"
	@echo "  make build-func   - build only the functional test image"
	@echo "  make build-perf   - build all performance test images"
	@echo "  make run-func     - build + run functional test"
	@echo "  make run-perf     - build + run all performance tests"
	@echo "  make run-all      - build + run functional + performance tests"
	@echo "  make report       - run full regression under Verilator"
	@echo "  make summary      - print CI status from latest report"
	@echo "  make clean-mem    - remove generated soc/sw/tests/*.mem"
	@echo "  make clean-reports - remove generated reports"
	@echo "  make clean        - remove .mem files and reports"

build:
	$(PYTHON) $(SOC)/scripts/build_tests.py -j 4

build-func:
	$(PYTHON) $(SOC)/scripts/build_tests.py -j 4 -t nscscc_func

build-perf:
	$(PYTHON) $(SOC)/scripts/build_tests.py -j 4 -t \
	  bitcount bubble_sort coremark crc32 dhrystone quick_sort select_sort \
	  sha stream_copy stringsearch fireye_A0 fireye_B2 fireye_C0 fireye_D1 \
	  fireye_I2 inner_product lookup_table loop_induction my_memcmp minmax_sequence

run-func: build-func
	$(PYTHON) $(SOC)/scripts/run_tests.py -t nscscc_func

run-perf: build-perf
	$(PYTHON) $(SOC)/scripts/run_tests.py -c performance

run-all: build
	$(PYTHON) $(SOC)/scripts/run_tests.py -c all

report:
	@$(PYTHON) $(SOC)/scripts/run_tests.py -c all -s verilator

summary:
	@$(PYTHON) $(SOC)/scripts/summarize_report.py

clean-mem:
	rm -f $(SOC)/sw/tests/*.mem

clean-reports:
	rm -rf $(SOC)/sw/tests/reports

clean: clean-mem clean-reports
	@echo "Cleaned generated .mem files and reports"
