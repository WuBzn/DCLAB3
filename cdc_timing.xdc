# DDR2 writes use a synchronized request. Top holds address/data from the
# request until transaction_complete, so this M_CLK-to-MIG path is a
# handshaked clock-domain crossing. Keep its physical delay below 10 ns.
# This file is used only in implementation, after the MIG clocks exist.
set_max_delay -datapath_only 10.000 -from [get_clocks clk_out5_clk_wiz_0] -to [get_clocks clk_pll_i]
