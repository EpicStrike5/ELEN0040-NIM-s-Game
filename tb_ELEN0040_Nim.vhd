-- ///
-- file : tb_ELEN0040_Nim.vhd
--
-- Main purpose : simulation testbench for the full Nim game top-level.
--               covers normal gameplay with bot auto-play, synchronous reset,
--               and two specific edge cases:
--                 (1) holding CONFIRM for multiple cycles -> must fire only once
--                 (2) pressing UP and CONFIRM simultaneously -> UP wins (priority)
--               do NOT add this file to Quartus synthesis.
--
-- Input  : none (self-contained)
--
-- Output : none (observe waveforms in Questa; stop(0) ends cleanly)
--
-- Button polarity : all btn_* default to '1' (pin pulled high = not pressed).
--                  press() drives '0' (pin shorted to GND = pressed), then
--                  releases to '1'. This matches real hardware behaviour.
--
-- Two-player : the bot has been temporarily removed to free LEs for the idle
--              carousel. Both turns are driven by this stimulus process.
--              wait_cycles(3) after each CONFIRM is generous slack; the state
--              transition happens on the very next clk1 rising edge.
--
-- How to run in Questa:
--   do compile.do
--   restart -f
--   do wave_setup.do
--   run -all
-- ///

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.nim_pkg.ALL;
use std.env.all;

entity tb_ELEN0040_Nim is
end entity tb_ELEN0040_Nim;

architecture sim of tb_ELEN0040_Nim is

    signal clk0        : std_logic := '0';
    signal clk1        : std_logic := '0';

    -- All buttons default '1' (not pressed = pin pulled high by RC).
    -- Driving '0' simulates the button shorting the pin to GND.
    signal btn_start   : std_logic := '1';
    signal btn_joker1  : std_logic := '1';
    signal btn_joker2  : std_logic := '1';
    signal btn_confirm : std_logic := '1';
    signal btn_up      : std_logic := '1';
    signal btn_down    : std_logic := '1';
    signal btn_reset   : std_logic := '1';

    signal sr_data     : std_logic;
    signal sr_clk      : std_logic;
    signal sr_latch    : std_logic;
    signal bcd_max_tk  : std_logic_vector(3 downto 0);
    signal bcd_sel     : std_logic_vector(3 downto 0);
    signal led_p1      : std_logic;
    signal led_p2      : std_logic;
    signal led_j1      : std_logic;
    signal led_j2      : std_logic;

    -- clocks sped up for simulation; 30:1 ratio matches the real board
    constant T0 : time :=  10 ns;
    constant T1 : time := 300 ns;

begin

    dut : entity work.ELEN0040_Nim
        port map (
            clk0        => clk0,
            clk1        => clk1,
            btn_start   => btn_start,
            btn_joker1  => btn_joker1,
            btn_joker2  => btn_joker2,
            btn_confirm => btn_confirm,
            btn_up      => btn_up,
            btn_down    => btn_down,
            btn_reset   => btn_reset,
            sr_data     => sr_data,
            sr_clk      => sr_clk,
            sr_latch    => sr_latch,
            bcd_max_tk  => bcd_max_tk,
            bcd_sel     => bcd_sel,
            led_p1      => led_p1,
            led_p2      => led_p2,
            led_j1      => led_j1,
            led_j2      => led_j2
        );

    clk0 <= not clk0 after T0 / 2;
    clk1 <= not clk1 after T1 / 2;

    -- safety net: kills simulation if stimulus process hangs unexpectedly
    timeout : process
    begin
        wait for 20 ms;
        report "TIMEOUT: simulation did not finish normally" severity failure;
    end process;

    stim : process

        -- Simulate one button press (active-low):
        --   drive '0' on the falling edge → nim_debounce sees a rising edge on raw
        --   release '1' after one period → db_edge fires for exactly ONE clk1 cycle
        procedure press(signal btn : out std_logic) is
        begin
            wait until falling_edge(clk1);
            btn <= '0';
            wait until rising_edge(clk1);
            wait until falling_edge(clk1);
            btn <= '1';
        end procedure;

        -- Hold a button pressed for `hold_cycles` clk1 periods then release.
        -- Used to verify that nim_debounce only generates ONE db_edge pulse
        -- regardless of hold duration (the 0->1 edge fires once, subsequent
        -- cycles see raw='1' and prev_raw='1', so db_edge='0').
        procedure press_hold(signal btn : out std_logic; hold_cycles : integer) is
        begin
            wait until falling_edge(clk1);
            btn <= '0';
            for i in 1 to hold_cycles loop
                wait until falling_edge(clk1);
            end loop;
            btn <= '1';
        end procedure;

        procedure wait_cycles(n : integer) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk1);
            end loop;
        end procedure;

    begin

        -- ----------------------------------------------------------------
        -- Phase 0: power-on IDLE
        -- Expected: led_p1='1', led_p2='1' (both on), joker LEDs off.
        -- ----------------------------------------------------------------
        report "Phase 0: IDLE - both player LEDs should be ON" severity note;
        wait_cycles(5);

        -- ----------------------------------------------------------------
        -- Phase 1: start the game
        -- rnd(0) picks the first player randomly. If bot goes first it acts
        -- on the very first S_PLAY cycle; wait 3 cycles to cover that.
        -- ----------------------------------------------------------------
        report "Phase 1: START game" severity note;
        press(btn_start);
        wait_cycles(3);

        -- ----------------------------------------------------------------
        -- Phase 2: P1 takes 2 sticks (UP then CONFIRM); P2's turn begins.
        -- ----------------------------------------------------------------
        report "Phase 2: P1 UP CONFIRM; P2 turn begins" severity note;
        press(btn_up);
        wait_cycles(1);
        press(btn_confirm);
        wait_cycles(3);

        -- ----------------------------------------------------------------
        -- Phase 3: human uses Joker 1 then confirms
        -- max_tk rerolled to 2..9; j1_p1 cleared; led_j1 goes low after press.
        -- ----------------------------------------------------------------
        report "Phase 3: human JOKER1 then CONFIRM" severity note;
        press(btn_joker1);
        wait_cycles(2);
        press(btn_confirm);
        wait_cycles(3);

        -- ----------------------------------------------------------------
        -- EDGE CASE 1: hold CONFIRM for 5 clk1 cycles
        --
        -- How it is handled:
        --   nim_debounce: db_edge = raw AND NOT prev_raw.
        --   Cycle 0: btn goes '0' → raw rises to '1', prev_raw='0' → db_edge='1' (fires once).
        --   Cycles 1-4: raw='1', prev_raw='1' → db_edge='0' (no retrigger).
        --   FSM sees CONFIRM exactly once regardless of hold duration.
        --
        -- Expected: bcd_sel = "0001" (sel reset to 1) after the hold, confirming
        --           the FSM processed the confirm only once. Bot then acts.
        -- ----------------------------------------------------------------
        report "EDGE CASE 1: hold CONFIRM 5 cycles - must fire once" severity note;
        press(btn_up);          -- ensure sel=2 so the confirm is clearly visible
        wait_cycles(1);
        press_hold(btn_confirm, 5);
        wait_cycles(1);
        -- sel should have reset to 1 (confirm fired once, player switched to bot)
        -- bot acts in the same cycle, then player switches back to human
        wait_cycles(2);
        assert bcd_sel = "0001"
            report "EDGE CASE 1 FAIL: bcd_sel=" &
                   integer'image(to_integer(unsigned(bcd_sel))) &
                   " expected 1 — confirm may have fired multiple times"
            severity warning;
        report "EDGE CASE 1: bcd_sel=" & integer'image(to_integer(unsigned(bcd_sel))) &
               " (expected 1 = fired once)" severity note;
        wait_cycles(1);

        -- ----------------------------------------------------------------
        -- EDGE CASE 2: press UP and CONFIRM simultaneously
        --
        -- How it is handled:
        --   Both btn_up and btn_confirm are driven '0' at the same falling edge.
        --   nim_debounce raises both db_edge bits in the same clk1 cycle.
        --   In nim_fsm S_PLAY the elsif chain checks UP before CONFIRM:
        --     UP fires  → sel increments.
        --     CONFIRM   → skipped (it is in a lower-priority elsif branch).
        --   Result: sel increases by 1, player does NOT switch, sticks unchanged.
        --
        -- Expected: bcd_sel > 1 (UP fired), player LEDs unchanged (no turn switch).
        -- ----------------------------------------------------------------
        report "EDGE CASE 2: simultaneous UP + CONFIRM - only UP should fire" severity note;
        wait until falling_edge(clk1);
        btn_up      <= '0';     -- both driven low at exactly the same moment
        btn_confirm <= '0';
        wait until rising_edge(clk1);
        wait until falling_edge(clk1);
        btn_up      <= '1';
        btn_confirm <= '1';
        wait_cycles(2);
        -- sel should be > 1 (UP fired), NOT = 1 (CONFIRM did not fire and reset it)
        assert bcd_sel /= "0001"
            report "EDGE CASE 2 FAIL: bcd_sel=1 implies CONFIRM fired - priority broken"
            severity warning;
        report "EDGE CASE 2: bcd_sel=" & integer'image(to_integer(unsigned(bcd_sel))) &
               " (expected > 1 = UP fired, CONFIRM ignored)" severity note;

        -- confirm the incremented selection normally to end the human's turn
        press(btn_confirm);
        wait_cycles(3);

        -- ----------------------------------------------------------------
        -- Phase 4: mid-game RESET test
        -- Assert btn_reset during S_PLAY; FSM must return to S_IDLE immediately.
        -- Expected: led_p1='1' and led_p2='1' (IDLE LED pattern).
        -- ----------------------------------------------------------------
        report "Phase 4: RESET mid-game - expect S_IDLE" severity note;
        wait until falling_edge(clk1);
        btn_reset <= '0';       -- assert reset (active-low pin)
        wait_cycles(2);         -- hold for 2 clk1 cycles
        btn_reset <= '1';       -- release
        wait_cycles(2);
        assert led_p1 = '1' and led_p2 = '1'
            report "Phase 4 FAIL: not in IDLE after reset"
            severity warning;
        report "Phase 4: led_p1=" & std_logic'image(led_p1) &
               " led_p2=" & std_logic'image(led_p2) &
               " (both '1' = IDLE)" severity note;

        -- ----------------------------------------------------------------
        -- Phase 5: second game - verify joker flags reset correctly on new START
        -- Joker 1 should be available again immediately after START.
        -- ----------------------------------------------------------------
        report "Phase 5: second game START - verify joker reset" severity note;
        press(btn_start);
        wait_cycles(3);         -- allow for bot-first case

        press(btn_joker1);      -- should work: j1_p1 was reset on START
        wait_cycles(2);
        press(btn_confirm);
        wait_cycles(3);

        -- ----------------------------------------------------------------
        -- Phase 6: grind remaining sticks to reach S_WIN
        -- Both players take max sticks each turn (testbench drives both).
        -- Loop runs past S_WIN safely (extra presses ignored in S_WIN / S_IDLE).
        -- ----------------------------------------------------------------
        report "Phase 6: grinding to S_WIN" severity note;
        for turn in 1 to 25 loop
            press(btn_up);      wait_cycles(1);
            press(btn_up);      wait_cycles(1);
            press(btn_confirm); wait_cycles(3);
        end loop;

        -- ----------------------------------------------------------------
        -- Phase 7: observe S_WIN then press START to return to IDLE
        -- ----------------------------------------------------------------
        report "Phase 7: S_WIN - observe winner blink, then START" severity note;
        wait_cycles(6);
        press(btn_start);
        wait_cycles(3);
        assert led_p1 = '1' and led_p2 = '1'
            report "Phase 7 FAIL: not back in IDLE after WIN->START"
            severity warning;
        report "Phase 7: back in IDLE - led_p1=" & std_logic'image(led_p1) &
               " led_p2=" & std_logic'image(led_p2) severity note;

        report "Simulation complete" severity note;
        stop(0);

    end process;

end architecture sim;
