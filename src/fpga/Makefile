SHELL := /bin/bash
.DEFAULT_GOAL := all
CC ?= cc
CFLAGS := -std=c11 -Wall -Wextra -Wpedantic
SHELLCHECK ?= shellcheck

SHELL_FILES := bin/fpga-dispatch bin/fpga-run $(wildcard scripts/*.sh tests/*.sh)
C_FILES := $(wildcard src/uart/*.c tests/*.c)
IVERILOG ?= iverilog
VVP ?= vvp

.PHONY: all test lint syntax
all: syntax
	@test -x bin/fpga-dispatch && test -x bin/fpga-run
	@echo 'Каркас готов; хостовая C-часть ещё не реализована.'

syntax:
	@for file in $(SHELL_FILES); do bash -n "$$file" || exit; done
	@jq empty config/integration.example.json

test: all
	@bash tests/scaffold.sh
	@bash tests/pipeline-placeholder.sh

lint: syntax
	@"$(SHELLCHECK)" $(SHELL_FILES)
	@for file in $(C_FILES); do $(CC) $(CPPFLAGS) $(CFLAGS) -fsyntax-only "$$file" || exit; done
	@echo 'Lint пройден; проверка C применится после появления исходников.'

.PHONY: test-led
test-led:
	@mkdir -p build
	$(IVERILOG) -g2001 -Wall -s tb_led_check -o build/tb_led_check tests/tb_led_check.v hdl/led_check.v
	$(VVP) build/tb_led_check

.PHONY: test-simulator probe-vendor
test-simulator:
	IVERILOG="$(IVERILOG)" VVP="$(VVP)" bash tests/simulator.sh

probe-vendor:
	@test -n "$(QUARTUS_ROOTDIR)" || { echo 'Set QUARTUS_ROOTDIR' >&2; exit 2; }
	@mkdir -p build
	$(IVERILOG) -g2001 -Wall -s tb_vendor_clock -o build/vendor-clock tests/tb_vendor_clock.v "$(QUARTUS_ROOTDIR)/eda/sim_lib/cyclonev_atoms.v"
	$(VVP) build/vendor-clock
