SHELL := /bin/bash
.DEFAULT_GOAL := all
CC ?= cc
CFLAGS := -std=c11 -Wall -Wextra -Wpedantic
SHELLCHECK ?= shellcheck

SHELL_FILES := bin/fpga-dispatch bin/fpga-run $(wildcard scripts/*.sh tests/*.sh)
C_FILES := $(wildcard src/uart/*.c src/runner/*.c tests/*.c)
IVERILOG ?= iverilog
VVP ?= vvp
QUARTUS_SH ?= quartus_sh
LAB4_HELPER ?= examples/lab4/student_sram_helper.v
SRAM_CHECK_HDL := tests/tb_sram_check.v hdl/sram_check.v hdl/c5g_sram_word.v hdl/jtag_snapshot.v
LAB4_HDL := hdl/lab4_evaluation.v hdl/lab4_text.v hdl/c5g_sram_word.v hdl/jtag_snapshot.v hdl/uart_rx.v hdl/uart_tx.v examples/lab4/student_sram_helper.v

.PHONY: build-jtag-probe
build-jtag-probe:
	cd quartus && "$(QUARTUS_SH)" --flow compile jtag_probe

.PHONY: build-sram-check test-sram-check build-sram-helper-check test-sram-helper-check
build-sram-check:
	cd quartus && "$(QUARTUS_SH)" --flow compile sram_check

build-sram-helper-check: export FPGA_HELPER_SOURCE := $(value LAB4_HELPER)
build-sram-helper-check: export FPGA_HELPER_QUARTUS := $(value QUARTUS_SH)
build-sram-helper-check: build/fpga-stage
	bash scripts/build-sram-helper.sh "$$FPGA_HELPER_SOURCE" "$$FPGA_HELPER_QUARTUS"

test-hdl: test-sram-check test-sram-helper-check
test-sram-check:
	@mkdir -p build
	$(IVERILOG) -g2001 -Wall -s tb_sram_check -o build/tb_sram_check $(SRAM_CHECK_HDL)
	$(VVP) build/tb_sram_check

test-sram-helper-check:
	@mkdir -p build
	@for variant in LAB4_GOOD LAB4_BAD_ADDRESS LAB4_BAD_DATA LAB4_SHORT_BUSY; do \
		$(IVERILOG) -g2001 -Wall -s tb_sram_check -Ptb_sram_check.CHECK_HELPER=1 -D$$variant \
			-o build/tb_sram_helper_$$variant $(SRAM_CHECK_HDL) examples/lab4/student_sram_helper.v && \
		$(VVP) build/tb_sram_helper_$$variant || exit; \
	done

.PHONY: build-lab4-evaluation test-lab4-evaluation
build-lab4-evaluation:
	cd quartus && "$(QUARTUS_SH)" --flow compile lab4_evaluation

test-hdl: test-lab4-evaluation
test-lab4-evaluation:
	@mkdir -p build
	$(IVERILOG) -g2001 -Wall -s tb_lab4_evaluation -o build/tb_lab4_evaluation tests/tb_lab4_evaluation.v tests/tb_lab3_evaluation.v $(LAB4_HDL)
	$(VVP) build/tb_lab4_evaluation

.PHONY: all test lint syntax
all: syntax build/test-serial build/fpga-uart build/fpga-uart-stimulus build/fpga-stage
	@test -x bin/fpga-dispatch && test -x bin/fpga-run
	@echo 'Host checks built; the dispatcher supports job registration.'

syntax:
	@for file in $(SHELL_FILES); do bash -n "$$file" || exit; done
	@jq empty config/integration.example.json

test: all build/test-uart-peer
	@$(MAKE) --no-print-directory test-serial
	@$(MAKE) --no-print-directory test-session
	@bash tests/scaffold.sh
	@bash tests/dispatch.sh
	@bash tests/runner.sh
	@bash tests/mock.sh
	@bash tests/launch.sh
	@bash tests/lifecycle.sh
	@bash tests/stage.sh
	@bash tests/contract.sh
	@bash tests/analyst-contract.sh
	@bash tests/display-observations.sh
	@bash tests/demo-submit.sh
	@bash tests/prepare-job.sh
	@bash tests/build-sram-helper.sh
	@$(MAKE) --no-print-directory test-protocol

lint: syntax
	@"$(SHELLCHECK)" $(SHELL_FILES)
	@for file in $(C_FILES); do $(CC) $(CPPFLAGS) $(CFLAGS) -fsyntax-only "$$file" || exit; done
	@echo 'PASS: shell and C lint'

build/test-serial: tests/serial.c src/uart/serial.c src/uart/serial.h
	@mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) tests/serial.c src/uart/serial.c -o $@

.PHONY: test-serial
test-serial: build/test-serial build/fpga-uart-stimulus
	./build/test-serial
	@./build/fpga-uart-stimulus --help >/dev/null
	@for hex in '' 0 gg; do ./build/fpga-uart-stimulus /dev/null even "$$hex" 1 2>/dev/null; test $$? -eq 2 || exit 1; done
	@for count in '' -1 65; do ./build/fpga-uart-stimulus /dev/null odd 00 "$$count" 2>/dev/null; test $$? -eq 2 || exit 1; done
	@echo 'PASS: serial PTY transport'

build/fpga-uart: src/uart/session.c src/uart/serial.c src/uart/serial.h
	@mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) src/uart/session.c src/uart/serial.c -o $@

build/fpga-uart-stimulus: src/uart/stimulus.c src/uart/serial.c src/uart/serial.h
	@mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) src/uart/stimulus.c src/uart/serial.c -o $@

build/test-session: tests/session.c
	@mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) $< -o $@

build/test-uart-peer: tests/uart-peer.c
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

.PHONY: test-clock test-hdl test-jtag-snapshot
test-hdl: test-simulator test-led test-clock test-clock-board test-uart-rx test-uart-tx test-uart-commands test-dut-control test-wrapper test-jtag-snapshot

test-jtag-snapshot:
	@mkdir -p build
	$(IVERILOG) -g2001 -Wall -s tb_jtag_snapshot -o build/tb_jtag_snapshot tests/tb_jtag_snapshot.v hdl/jtag_snapshot.v
	$(VVP) build/tb_jtag_snapshot

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

.PHONY: build-lab3-uart-probe test-lab3-uart-probe test-lab3-uart-hardware
build-lab3-uart-probe:
	cd quartus && "$${QUARTUS_SH:-quartus_sh}" --flow compile lab3_uart_probe

test-hdl: test-lab3-uart-probe

test-lab3-uart-probe:
	@mkdir -p build
	$(IVERILOG) -g2001 -Wall -s tb_lab3_uart_probe -o build/tb_lab3_uart_probe tests/tb_lab3_uart_probe.v hdl/lab3_uart_probe.v hdl/uart_rx.v hdl/uart_tx.v
	$(VVP) build/tb_lab3_uart_probe

test-lab3-uart-hardware: build/fpga-uart-stimulus
	@bash tests/lab3-uart-hardware.sh "$${UART_PORT:-}"

.PHONY: build-lab3-evaluation test-lab3-evaluation
build-lab3-evaluation:
	cd quartus && "$(QUARTUS_SH)" --flow compile lab3_evaluation

test-hdl: test-lab3-evaluation

test-lab3-evaluation:
	IVERILOG="$(IVERILOG)" VVP="$(VVP)" bash tests/lab3-evaluation.sh
