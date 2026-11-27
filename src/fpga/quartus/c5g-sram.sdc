create_clock -name clk -period 20.000 [get_ports clk]
derive_clock_uncertainty
# Budget FPGA I/O paths within a 20 ns cycle; the controller holds each
# external transaction over multiple cycles for the device access time.
set sram_outputs [get_ports {sram_a[*] sram_d[*] ce_n oe_n we_n lb_n ub_n}]
set_output_delay -clock clk -max 8.0 $sram_outputs
set_output_delay -clock clk -min 0.0 $sram_outputs
set_input_delay -clock clk -max 8.0 [get_ports {sram_d[*]}]
set_input_delay -clock clk -min 0.0 [get_ports {sram_d[*]}]
