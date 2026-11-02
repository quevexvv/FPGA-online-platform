create_clock -name clk -period 20.000 [get_ports {clk}]

derive_clock_uncertainty

# LED is a visual indicator with no external sampling clock.
set_false_path -to [get_ports {led}]