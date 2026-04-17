# =============================================================================
# wave_setup.do  --  Questa wave window setup for ELEN0040_Nim simulation
#
# Usage (in Questa transcript after simulation loads):
#   do wave_setup.do
#   restart -f
#   run -all
# =============================================================================

# Clear existing wave window
wave zoom full

add wave -divider "--- CLOCKS ---"
add wave -color cyan  /tb_elen0040_nim/clk0
add wave -color cyan  /tb_elen0040_nim/clk1

add wave -divider "--- BUTTONS ---"
add wave -color yellow /tb_elen0040_nim/btn_start
add wave -color yellow /tb_elen0040_nim/btn_joker1
add wave -color yellow /tb_elen0040_nim/btn_joker2
add wave -color yellow /tb_elen0040_nim/btn_confirm
add wave -color yellow /tb_elen0040_nim/btn_up
add wave -color yellow /tb_elen0040_nim/btn_down

add wave -divider "--- FSM STATE ---"
add wave -color white  /tb_elen0040_nim/dut/u_fsm/state_r
add wave -color white  /tb_elen0040_nim/dut/u_fsm/player_r
add wave -color white -format unsigned /tb_elen0040_nim/dut/u_fsm/sticks_r
add wave -color white -format unsigned /tb_elen0040_nim/dut/u_fsm/sel_r
add wave -color white -format unsigned /tb_elen0040_nim/dut/u_fsm/max_tk_r

add wave -divider "--- JOKER FLAGS (internal) ---"
add wave -color orange /tb_elen0040_nim/dut/u_fsm/j1_p1
add wave -color orange /tb_elen0040_nim/dut/u_fsm/j1_p2
add wave -color orange /tb_elen0040_nim/dut/u_fsm/j2_p1
add wave -color orange /tb_elen0040_nim/dut/u_fsm/j2_p2

add wave -divider "--- BCD OUTPUTS ---"
add wave -color green -format unsigned /tb_elen0040_nim/bcd_max_tk
add wave -color green -format unsigned /tb_elen0040_nim/bcd_sel

add wave -divider "--- PLAYER & JOKER LEDS ---"
add wave -color green  /tb_elen0040_nim/led_p1
add wave -color green  /tb_elen0040_nim/led_p2
add wave -color orange /tb_elen0040_nim/led_j1
add wave -color orange /tb_elen0040_nim/led_j2

add wave -divider "--- SR CHAIN ---"
add wave -color magenta /tb_elen0040_nim/sr_data
add wave -color magenta /tb_elen0040_nim/sr_clk
add wave -color magenta /tb_elen0040_nim/sr_latch
