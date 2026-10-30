create_clock -name clk -period 20.000 [get_ports {clk}]
create_generated_clock -name dut_clk -source [get_ports {clk}] -divide_by 50 [get_registers {*|dut_clk}]
derive_clock_uncertainty
# No exceptions between control, reset and diagnostic counter domains.
# Only unsampled visual LED outputs are excluded.
set_false_path -to [get_ports {led[*]}]
