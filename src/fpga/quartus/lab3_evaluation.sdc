create_clock -name clk -period 20.000 [get_ports {clk}]
derive_clock_uncertainty
set_false_path -from [get_ports {rx}] -to [get_registers {*receiver|rx_meta *monitor|rx_meta}]
set_false_path -to [get_ports {tx hex0[*] hex1[*] hex2[*] hex3[*]}]
