# wave_setup.do  --  Questa wave window setup for ELEN0040_Nim simulation
#
# Usage:
#   do compile.do
#   vsim work.tb_ELEN0040_Nim
#   view wave
#   do wave_setup.do
#   run -all

add wave -divider {CLOCKS}
add wave -color cyan  /tb_elen0040_nim/clk0
add wave -color cyan  /tb_elen0040_nim/clk1

add wave -divider {BUTTONS}
add wave -color yellow /tb_elen0040_nim/btn_start
add wave -color yellow /tb_elen0040_nim/btn_joker1
add wave -color yellow /tb_elen0040_nim/btn_joker2
add wave -color yellow /tb_elen0040_nim/btn_confirm
add wave -color yellow /tb_elen0040_nim/btn_up
add wave -color yellow /tb_elen0040_nim/btn_down
add wave -color red    /tb_elen0040_nim/btn_reset

add wave -divider {FSM STATE}
add wave -color white  /tb_elen0040_nim/dut/u_fsm/state_r
add wave -color white  /tb_elen0040_nim/dut/u_fsm/player_r
add wave -color white -format unsigned /tb_elen0040_nim/dut/u_fsm/sticks_r
add wave -color white -format unsigned /tb_elen0040_nim/dut/u_fsm/selection_r
add wave -color white -format unsigned /tb_elen0040_nim/dut/u_fsm/max_take_r

add wave -divider {IDLE CAROUSEL}
add wave -color cyan -format unsigned /tb_elen0040_nim/dut/carousel_r

add wave -divider {RANDOM SOURCE}
add wave -color cyan -format unsigned /tb_elen0040_nim/dut/u_sr/sr_cnt

add wave -divider {JOKER FLAGS}
add wave -color orange /tb_elen0040_nim/dut/u_fsm/joker1_p1
add wave -color orange /tb_elen0040_nim/dut/u_fsm/joker1_p2
add wave -color orange /tb_elen0040_nim/dut/u_fsm/joker2_p1
add wave -color orange /tb_elen0040_nim/dut/u_fsm/joker2_p2

add wave -divider {BCD OUTPUTS}
add wave -color green -format unsigned /tb_elen0040_nim/bcd_max_tk
add wave -color green -format unsigned /tb_elen0040_nim/bcd_sel

add wave -divider {PLAYER AND JOKER LEDS}
add wave -color green  /tb_elen0040_nim/led_p1
add wave -color green  /tb_elen0040_nim/led_p2
add wave -color orange /tb_elen0040_nim/led_j1
add wave -color orange /tb_elen0040_nim/led_j2

add wave -divider {SR CHAIN}
add wave -color magenta /tb_elen0040_nim/sr_data
add wave -color magenta /tb_elen0040_nim/sr_clk
add wave -color magenta /tb_elen0040_nim/sr_latch
