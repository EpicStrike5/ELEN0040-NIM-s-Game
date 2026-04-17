# =============================================================================
# compile.do  --  Recompile all ELEN0040_Nim sources in Questa
# Usage: do compile.do
# =============================================================================
vcom -work work "C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/nim_pkg.vhd"
vcom -work work "C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/nim_debounce.vhd"
vcom -work work "C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/nim_sr.vhd"
vcom -work work "C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/nim_fsm.vhd"
vcom -work work "C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/ELEN0040_Nim.vhd"
vcom -work work "C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/tb_ELEN0040_Nim.vhd"
