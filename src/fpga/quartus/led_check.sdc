create_clock -name clk -period 20.000 [get_ports {clk}]
derive_clock_uncertainty
# Visual indicators have no external sampling clock.
set_false_path -to [get_ports {led[*]}]
