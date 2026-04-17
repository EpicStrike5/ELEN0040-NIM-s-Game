# ELEN0040 — Nim Game on Intel MAX V CPLD

VHDL implementation of the Nim game for the ELEN0040 Digital Electronics course at ULiège.
Target device: **Intel MAX V 5M160ZE64C4** (160 macrocells, 64-pin EQFP).

## Game rules

This is the **misère** variant of Nim:
- The game starts with **21 sticks**.
- Players alternate turns. On each turn, a player takes 1 to `max_tk` sticks.
- The player who takes the **last stick loses**.
- Each player has two jokers (one of each type, usable once per game):
  - **Joker 1** — rerolls `max_tk` to a random value between 2 and 9.
  - **Joker 2** — randomly adds or removes 1 to 4 sticks from the pile.

## Hardware

| Component | Part | Role |
|---|---|---|
| CPLD | Intel MAX V 5M160ZE64C4 | Game logic |
| Shift registers | 5x TLC6C598 (daisy-chained) | Drive 40 stick LEDs |
| LED bars | 4x LTA-1000G/Y | Show remaining sticks |
| 7-seg decoders | 2x CD4511BEE4 | Display max_tk and sel |
| Clocks | 2x LMC555CN | clk0 (59-320 Hz), clk1 (0.7-48 Hz) |
| Buttons | 6x SPST-NO | Start, Confirm, Up, Down, Joker1, Joker2 |

**Power:** USB-C 5V for everything. The CPLD dev board produces VCCINT (1.86V) and VCCIO (3.1V) internally from the 5V input.

**Buttons** use a 10k pull-up to VCCIO + 100nF RC filter. They are active-low at the CPLD pin and inverted in the top-level VHDL.

**Stick LEDs** are common-anode bars. The TLC6C598 open-drain outputs sink current through 270Ω resistor arrays. IC1 DRAIN0 = LED 0.

## VHDL file structure

| File | Role |
|---|---|
| `nim_pkg.vhd` | Shared types and button index constants — compile first |
| `nim_debounce.vhd` | Rising-edge detector for all 6 buttons |
| `nim_sr.vhd` | Shift register serialiser (40-bit frame, clk0 domain) |
| `nim_fsm.vhd` | Game state machine (clk0 domain) |
| `ELEN0040_Nim.vhd` | Top-level: wires everything together |
| `tb_ELEN0040_Nim.vhd` | Simulation testbench (do not add to synthesis) |

## Resource usage

Last confirmed synthesis (Quartus Prime Lite 23.1):

| Resource | Used | Limit |
|---|---|---|
| Logic elements | 134 | 160 |
| I/O pins | 23 | 36 |

## Quartus setup

1. Open `ELEN0040_Nim.qpf`.
2. Ensure files are added in this compile order in the QSF:
   `nim_pkg.vhd` → `nim_debounce.vhd` → `nim_sr.vhd` → `nim_fsm.vhd` → `ELEN0040_Nim.vhd`
3. Device: `5M160ZE64C4`, speed grade C4.
4. Recommended QSF settings:
   ```
   set_global_assignment -name OPTIMIZATION_MODE "Aggressive Area"
   set_global_assignment -name STATE_MACHINE_PROCESSING Sequential
   ```
5. Run full compilation, then assign pins in the Pin Planner before programming.

## Simulation in Questa

Recompile after any file change:
```
do compile.do
restart -f
do wave_setup.do
run -all
```

`wave_setup.do` loads a pre-configured wave window with labelled signal groups including internal FSM signals (state, sticks, joker flags).

## Pin assignments

| Signal | Direction | Connected to |
|---|---|---|
| clk0 | in | LMC555 #0 output (dedicated CLK pin) |
| clk1 | in | LMC555 #1 output (dedicated CLK pin) |
| btn_start/joker1/joker2/confirm/up/down | in | 74LVC14A outputs (active-low, RC debounced) |
| sr_data / sr_clk / sr_latch | out | TLC6C598 IC1 SER_IN / SRCK / RCK |
| bcd_max_tk[3:0] | out | CD4511 #1 pins D/C/B/A |
| bcd_sel[3:0] | out | CD4511 #2 pins D/C/B/A |
| led_p1 / led_p2 | out | Player indicator LEDs |
| led_j1 / led_j2 | out | Joker availability LEDs |

## Authors

Thomas — ULiège, 2025-2026
