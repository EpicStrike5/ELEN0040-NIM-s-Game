transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vcom -93 -work work {C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/nim_pkg.vhd}
vcom -93 -work work {C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/nim_debounce.vhd}
vcom -93 -work work {C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/nim_sr.vhd}
vcom -93 -work work {C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/nim_fsm.vhd}
vcom -93 -work work {C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/ELEN0040_Nim.vhd}

vcom -93 -work work {C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/tb_ELEN0040_Nim.vhd}

vsim -t 1ps -L altera -L lpm -L sgate -L altera_mf -L altera_lnsim -L maxv -L rtl_work -L work -voptargs="+acc"  tb_ELEN0040_Nim

add wave *
view structure
view signals
run -all
