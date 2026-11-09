SHELL := /bin/bash
.DEFAULT_GOAL := all
CC ?= cc
CFLAGS := -std=c11 -Wall -Wextra -Wpedantic
SHELLCHECK ?= shellcheck

SHELL_FILES := bin/fpga-dispatch bin/fpga-run $(wildcard scripts/*.sh tests/*.sh)
C_FILES := $(wildcard src/uart/*.c src/runner/*.c tests/*.c)
IVERILOG ?= iverilog
VVP ?= vvp

.PHONY: all test lint syntax
all: syntax build/test-serial build/fpga-uart build/fpga-stage
	@test -x bin/fpga-dispatch && test -x bin/fpga-run
	@echo 'Host checks built; the dispatcher supports job registration.'

syntax:
	@for file in $(SHELL_FILES); do bash -n "$$file" || exit; done
	@jq empty config/integration.example.json

test: all
	@$(MAKE) --no-print-directory test-serial
	@$(MAKE) --no-print-directory test-session
	@bash tests/scaffold.sh
	@bash tests/dispatch.sh
	@bash tests/runner.sh
	@bash tests/stage.sh
	@bash tests/contract.sh
	@bash tests/analyst-contract.sh
	@bash tests/prepare-job.sh
	@$(MAKE) --no-print-directory test-protocol

lint: syntax
	@"$(SHELLCHECK)" $(SHELL_FILES)
	@for file in $(C_FILES); do $(CC) $(CPPFLAGS) $(CFLAGS) -fsyntax-only "$$file" || exit; done
	@echo 'PASS: shell and C lint'

build/test-serial: tests/serial.c src/uart/serial.c src/uart/serial.h
	@mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) tests/serial.c src/uart/serial.c -o $@

.PHONY: test-serial
test-serial: build/test-serial
	./build/test-serial
	@echo 'PASS: serial PTY transport'

build/fpga-uart: src/uart/session.c src/uart/serial.c src/uart/serial.h
	@mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) src/uart/session.c src/uart/serial.c -o $@

build/test-session: tests/session.c
	@mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) $< -o $@

build/fpga-stage: src/runner/stage.c
	@mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) $< -o $@

.PHONY: test-session
test-session: build/fpga-uart build/test-session
	./build/test-session
	@./build/fpga-uart --help >/dev/null
	@for timeout in 0 60001 -1 text; do ./build/fpga-uart /dev/null "$$timeout" 2>/dev/null; test $$? -eq 2 || exit 1; done
	@echo 'PASS: UART session PTY commands and failures'

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

.PHONY: test-contract
test-contract:
	@bash tests/contract.sh

.PHONY: test-clock test-hdl
test-hdl: test-simulator test-led test-clock test-clock-board test-uart-rx test-uart-tx test-uart-commands test-dut-control test-wrapper

WRAPPER_HDL := hdl/fpga_wrapper.v hdl/dut_control.v hdl/clock_burst.v hdl/uart_service.v hdl/uart_commands.v hdl/uart_rx.v hdl/uart_tx.v
.PHONY: test-wrapper
test-wrapper:
	@mkdir -p build
	$(IVERILOG) -g2001 -Wall -s tb_fpga_wrapper -o build/tb_wrapper_counter tests/tb_fpga_wrapper.v $(WRAPPER_HDL) examples/counter/student_top.v
	$(VVP) build/tb_wrapper_counter
	$(IVERILOG) -g2001 -Wall -s tb_fpga_wrapper -Ptb_fpga_wrapper.COMBINATIONAL=1 -o build/tb_wrapper_combinational tests/tb_fpga_wrapper.v $(WRAPPER_HDL) examples/combinational/student_top.v
	$(VVP) build/tb_wrapper_combinational

.PHONY: test-hardware
test-hardware: build/fpga-uart
	@bash tests/step-hardware.sh "$${UART_PORT:-}"

.PHONY: test-dut-control
test-dut-control:
	@mkdir -p build
	$(IVERILOG) -g2001 -Wall -s tb_dut_control -o build/tb_dut_control tests/tb_dut_control.v hdl/dut_control.v hdl/clock_burst.v
	$(VVP) build/tb_dut_control

.PHONY: test-uart-commands
test-uart-commands:
	@mkdir -p build
	$(IVERILOG) -g2001 -Wall -s tb_uart_commands -o build/tb_uart_commands tests/tb_uart_commands.v hdl/uart_commands.v
	$(VVP) build/tb_uart_commands

test-clock:
	@mkdir -p build
	$(IVERILOG) -g2001 -Wall -s tb_clock_burst -o build/tb_clock_burst tests/tb_clock_burst.v hdl/clock_burst.v
	$(VVP) build/tb_clock_burst
	$(IVERILOG) -g2001 -Wall -s tb_clock_burst -Ptb_clock_burst.HALF_PERIOD=25 -o build/tb_clock_burst_25 tests/tb_clock_burst.v hdl/clock_burst.v
	$(VVP) build/tb_clock_burst_25

.PHONY: test-clock-board
test-clock-board:
	@mkdir -p build
	$(IVERILOG) -g2001 -Wall -s tb_clock_board -o build/tb_clock_board tests/tb_clock_board.v hdl/clock_board.v hdl/clock_burst.v
	$(VVP) build/tb_clock_board

.PHONY: test-protocol
test-protocol:
	@jq -e -f tests/protocol.jq examples/uart-frames.json >/dev/null
	@echo 'PASS: UART protocol frame table'

.PHONY: test-uart-rx
test-uart-rx:
	@mkdir -p build
	$(IVERILOG) -g2001 -Wall -s tb_uart_rx -o build/tb_uart_rx tests/tb_uart_rx.v hdl/uart_rx.v
	$(VVP) build/tb_uart_rx
	$(IVERILOG) -g2001 -Wall -s tb_uart_rx -Ptb_uart_rx.CLKS_PER_BIT=434 -o build/tb_uart_rx_434 tests/tb_uart_rx.v hdl/uart_rx.v
	$(VVP) build/tb_uart_rx_434

.PHONY: test-uart-tx
test-uart-tx:
	@mkdir -p build
	$(IVERILOG) -g2001 -Wall -s tb_uart_tx -o build/tb_uart_tx tests/tb_uart_tx.v hdl/uart_tx.v
	$(VVP) build/tb_uart_tx
	$(IVERILOG) -g2001 -Wall -s tb_uart_tx -Ptb_uart_tx.CLKS_PER_BIT=434 -o build/tb_uart_tx_434 tests/tb_uart_tx.v hdl/uart_tx.v
	$(VVP) build/tb_uart_tx_434
