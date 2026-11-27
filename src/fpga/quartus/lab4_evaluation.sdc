source c5g-sram.sdc
set_false_path -from [get_ports {rx}] -to [get_registers {*receiver|rx_meta}]
set_false_path -to [get_ports {tx hex0[*] hex1[*] hex2[*] hex3[*]}]
