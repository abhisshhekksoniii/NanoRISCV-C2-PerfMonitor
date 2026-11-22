# Clock: 20 ns period (50 MHz)
create_clock -period 20.000 -name clk [get_ports clk]

# Asynchronous reset is not timed synchronously
set_false_path -from [get_ports reset]