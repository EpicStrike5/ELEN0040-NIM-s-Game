# =============================================================================
# compile.do  --  Recompile all ELEN0040_Nim sources in Questa
#
# Usage: in the Questa transcript, just run:
#   do {C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/compile.do}
#
# -2008 is required for std.env (stop) used in the testbench.
# =============================================================================
catch {quit -sim}
cd {C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet}
vcom -2008 -work work "C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/nim_pkg.vhd"
vcom -2008 -work work "C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/nim_debounce.vhd"
vcom -2008 -work work "C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/nim_sr.vhd"
vcom -2008 -work work "C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/nim_fsm.vhd"
vcom -2008 -work work "C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/ELEN0040_Nim.vhd"
vcom -2008 -work work "C:/Users/Thomas/Documents/Uliege/Digital Electronics/Projet/tb_ELEN0040_Nim.vhd"
