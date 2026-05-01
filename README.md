# ELEN0040 — Nim Game on Intel MAX V CPLD

VHDL implementation of the two-player Nim game for the ELEN0040 Digital
Electronics course at ULiège.  
Target device: **Intel MAX V 5M160ZE64C4** (160 macrocells, 64-pin EQFP).

---

## Game rules

Misère variant of Nim:

- The pile starts with a **random number of sticks (9–40)**, picked at game start.
- Players alternate turns. On each turn a player takes between **1 and `max_take`** sticks (default: 3).
- The player who takes the **last stick loses**.
- Each player has **two one-use jokers** per game:
  - **Joker 1** — rerolls `max_take` to a random value in [4, 9]. Fires on button **release**.
  - **Joker 2** — randomly adds or removes sticks (amount clamped to current selection). Fires on button **release**.

---

## File structure

| File | Role |
|---|---|
| `nim_pkg.vhd` | Shared types and button index constants — **compile first** |
| `nim_debounce.vhd` | Edge detector: one-cycle press and release pulses for all 6 buttons |
| `nim_sr.vhd` | Shift-register serialiser — 40-bit frame on `clk0`; exposes counter as random source |
| `nim_fsm.vhd` | Game state machine — all logic on `clk1` |
| `ELEN0040_Nim.vhd` | Top-level: wires all sub-modules together |
| `tb_ELEN0040_Nim.vhd` | Questa testbench — do not add to Quartus synthesis |
| `compile.do` | Questa compilation script |
| `wave_setup.do` | Pre-configured wave window for simulation |

---

## Resource usage

Last confirmed synthesis (Quartus Prime Lite 23.1):

| Resource | Used | Available |
|---|---|---|
| Logic elements | 134 | 160 |
| I/O pins | 23 | 36 |

---

## How to open in Quartus

1. Open `ELEN0040_Nim.qpf`.
2. Device: `5M160ZE64C4`, speed grade **C4**.
3. Compile order in QSF: `nim_pkg` → `nim_debounce` → `nim_sr` → `nim_fsm` → `ELEN0040_Nim`.
4. Run full compilation then program via JTAG.

Recommended QSF settings (already included):
```
set_global_assignment -name OPTIMIZATION_MODE "Aggressive Area"
set_global_assignment -name STATE_MACHINE_PROCESSING Sequential
```

---

## How to simulate in Questa

```tcl
do compile.do
restart -f
do wave_setup.do
run -all
```

---

## Authors

Thomas & Luca — ULiège, 2025–2026
