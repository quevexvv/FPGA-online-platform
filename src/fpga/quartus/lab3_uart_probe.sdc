create_clock -name clk -period 20.000 [get_ports {clk}]
derive_clock_uncertainty

# The first RX synchronizer and the serial TX pin are asynchronous.
set_false_path -from [get_ports {rx}] -to [get_registers {*receiver|rx_meta}]
set_false_path -to [get_ports {tx}]
