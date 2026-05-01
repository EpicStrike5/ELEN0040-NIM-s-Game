-- ///
-- file : tb_ELEN0040_Nim.vhd
-- Main purpose : full simulation of the Nim game. Do NOT add to Quartus synthesis.
-- How to run   : do compile.do -> vsim work.tb_ELEN0040_Nim -> view wave -> do wave_setup.do -> run -all
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

    -- Buttons default '1' (released). Driving '0' simulates a press (active-low hardware).
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

    -- Clocks sped up for simulation; 
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

    -- Kill simulation if the stimulus process hangs
    timeout : process
    begin
        wait for 20 ms;
        report "TIMEOUT: simulation did not finish normally" severity failure;
    end process;

    stim : process

        -- Press a button for exactly one clk1 cycle then release
        procedure press(signal btn : out std_logic) is
        begin
            wait until falling_edge(clk1);
            btn <= '0';
            wait until rising_edge(clk1);
            wait until falling_edge(clk1);
            btn <= '1';
        end procedure;

        -- Hold a button for hold_cycles clk1 periods (tests that db_edge fires only once)
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

        -- Phase 0: power-on idle — both player LEDs should be on
        report "Phase 0: IDLE - both player LEDs should be ON" severity note;
        wait_cycles(5);

        -- Phase 1: start a game (rnd picks first player and stick count)
        report "Phase 1: START game" severity note;
        press(btn_start);
        wait_cycles(3);

        -- Phase 2: player takes 2 sticks (UP then CONFIRM)
        report "Phase 2: P1 UP CONFIRM; P2 turn begins" severity note;
        press(btn_up);
        wait_cycles(1);
        press(btn_confirm);
        wait_cycles(3);

        -- Phase 3: use Joker 1 to reroll max_take, then confirm
        report "Phase 3: human JOKER1 then CONFIRM" severity note;
        press(btn_joker1);
        wait_cycles(2);
        press(btn_confirm);
        wait_cycles(3);

        -- Edge case 1: hold CONFIRM for 5 cycles — FSM must only fire once
        report "EDGE CASE 1: hold CONFIRM 5 cycles - must fire once" severity note;
        press(btn_up);
        wait_cycles(1);
        press_hold(btn_confirm, 5);
        wait_cycles(3);
        assert bcd_sel = "0001"
            report "EDGE CASE 1 FAIL: bcd_sel=" &
                   integer'image(to_integer(unsigned(bcd_sel))) &
                   " expected 1 - confirm may have fired multiple times"
            severity warning;
        report "EDGE CASE 1: bcd_sel=" & integer'image(to_integer(unsigned(bcd_sel))) &
               " (expected 1 = fired once)" severity note;
        wait_cycles(1);

        -- Edge case 2: UP and CONFIRM pressed simultaneously — UP must win (higher priority)
        report "EDGE CASE 2: simultaneous UP + CONFIRM - only UP should fire" severity note;
        wait until falling_edge(clk1);
        btn_up      <= '0';
        btn_confirm <= '0';
        wait until rising_edge(clk1);
        wait until falling_edge(clk1);
        btn_up      <= '1';
        btn_confirm <= '1';
        wait_cycles(2);
        assert bcd_sel /= "0001"
            report "EDGE CASE 2 FAIL: bcd_sel=1 implies CONFIRM fired - priority broken"
            severity warning;
        report "EDGE CASE 2: bcd_sel=" & integer'image(to_integer(unsigned(bcd_sel))) &
               " (expected > 1 = UP fired, CONFIRM ignored)" severity note;
        press(btn_confirm);
        wait_cycles(3);

        -- Phase 4: reset mid-game — FSM must return to S_IDLE immediately
        report "Phase 4: RESET mid-game - expect S_IDLE" severity note;
        wait until falling_edge(clk1);
        btn_reset <= '0';
        wait_cycles(2);
        btn_reset <= '1';
        wait_cycles(2);
        assert led_p1 = '1' and led_p2 = '1'
            report "Phase 4 FAIL: not in IDLE after reset" severity warning;
        report "Phase 4: led_p1=" & std_logic'image(led_p1) &
               " led_p2=" & std_logic'image(led_p2) &
               " (both '1' = IDLE)" severity note;

        -- Phase 5: start a second game and verify joker flags were reset by START
        report "Phase 5: second game START - verify joker reset" severity note;
        press(btn_start);
        wait_cycles(3);
        press(btn_joker1);
        wait_cycles(2);
        press(btn_confirm);
        wait_cycles(3);

        -- Phase 6: grind sticks down to zero to reach S_WIN
        report "Phase 6: grinding to S_WIN" severity note;
        for turn in 1 to 25 loop
            press(btn_up);      wait_cycles(1);
            press(btn_up);      wait_cycles(1);
            press(btn_confirm); wait_cycles(3);
        end loop;

        -- Phase 7: observe winner blink then return to idle via START
        report "Phase 7: S_WIN - observe winner blink, then START" severity note;
        wait_cycles(6);
        press(btn_start);
        wait_cycles(3);
        assert led_p1 = '1' and led_p2 = '1'
            report "Phase 7 FAIL: not back in IDLE after WIN->START" severity warning;
        report "Phase 7: back in IDLE - led_p1=" & std_logic'image(led_p1) &
               " led_p2=" & std_logic'image(led_p2) severity note;

        report "Simulation complete" severity note;
        stop(0);

    end process;

end architecture sim;
