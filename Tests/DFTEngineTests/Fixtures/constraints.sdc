create_clock -name scan_clk -period 10 [get_ports scan_clk]
set_case_analysis 1 [get_ports test_mode]
set_case_analysis 1 [get_ports scan_en]
