create_clock -name clk -period 20.000 [get_ports {clk}]
create_generated_clock -name dut_clk -source [get_ports {clk}] -divide_by 50 [get_registers {*|dut_clk}]
derive_clock_uncertainty
# Bursts may start on any source-clock edge. Transfers use the guaranteed
# 500 ns low settling interval, not the nominal divided-clock phase.
set dut_registers [get_registers {*student|*}]
if {[get_collection_size $dut_registers] > 0} {
    set_max_delay 480 -from [get_registers {*|din* *|dut_reset}] -to $dut_registers
    set_max_delay 480 -from $dut_registers -to [get_registers {*|snapshot*}]
}
# Only the first RX synchronizer stage is asynchronous.
set_false_path -from [get_ports {rx}] -to [get_registers {*receiver|rx_meta}]
# UART TX and visual LEDs are not sampled by an external synchronous clock.
set_false_path -to [get_ports {tx led[*]}]
