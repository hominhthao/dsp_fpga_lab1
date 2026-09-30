create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

derive_pll_clocks
derive_clock_uncertainty

set_false_path \
    -from [get_registers {*u_i2s|sample_req_toggle*}] \
    -to   [get_registers {*u_sample_sync|sync_ff1*}]

set_false_path \
    -from [get_registers {*audio_sample_hold*}] \
    -to   [get_registers {*u_i2s|frame_sample*}]
