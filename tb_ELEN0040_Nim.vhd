-- ///
-- file : tb_ELEN0040_Nim.vhd
--
-- Main purpose : simulation testbench for the full Nim game top-level.
--               runs a scripted 10-phase game covering every button,
--               both players, all four joker uses, and a second game
--               to verify joker flag reset. do NOT add to Quartus synthesis.
--
-- Input  : none (self-contained; clocks and stimuli generated internally)
--
-- Output : none (waveforms observed in Questa; stop(0) ends simulation cleanly)
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
    signal btn_start   : std_logic := '0';
    signal btn_joker1  : std_logic := '0';
    signal btn_joker2  : std_logic := '0';
    signal btn_confirm : std_logic := '0';
    signal btn_up      : std_logic := '0';
    signal btn_down    : std_logic := '0';
    signal sr_data     : std_logic;
    signal sr_clk      : std_logic;
    signal sr_latch    : std_logic;
    signal bcd_max_tk  : std_logic_vector(3 downto 0);
    signal bcd_sel     : std_logic_vector(3 downto 0);
    signal led_p1      : std_logic;
    signal led_p2      : std_logic;
    signal led_j1      : std_logic;
    signal led_j2      : std_logic;

    -- clocks sped up for simulation; ratio 30:1 matches real board (clk0/clk1)
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

    -- free-running clocks
    clk0 <= not clk0 after T0 / 2;
    clk1 <= not clk1 after T1 / 2;

    -- safety net: kills simulation if stimulus hangs unexpectedly
    timeout : process
    begin
        wait for 10 ms;
        report "TIMEOUT: simulation did not finish normally" severity failure;
    end process;

    stim : process

        -- assert button on the falling edge, release after the next rising edge
        -- this guarantees nim_debounce sees exactly one rising edge per press
        procedure press(signal btn : out std_logic) is
        begin
            wait until falling_edge(clk1);
            btn <= '1';
            wait until rising_edge(clk1);
            wait until falling_edge(clk1);
            btn <= '0';
        end procedure;

        procedure wait_cycles(n : integer) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk1);
            end loop;
        end procedure;

    begin

        -- Phase 0: power-on IDLE (both player LEDs on, joker LEDs off)
        report "Phase 0: IDLE" severity note;
        wait_cycles(5);

        -- Phase 1: START -> sticks=21, max_tk=3, sel=1, all joker flags = 1
        report "Phase 1: START" severity note;
        press(btn_start);
        wait_cycles(2);

        -- Phase 2: Player A takes 3 sticks (UP UP CONFIRM) -> sticks 21->18
        report "Phase 2: Turn 1 (P_A) UP UP CONFIRM -> sticks 21->18" severity note;
        press(btn_up);      wait_cycles(1);
        press(btn_up);      wait_cycles(1);
        press(btn_confirm); wait_cycles(2);

        -- Phase 3: Player B uses Joker 1 -> max_tk rerolled; j1 flag for P_B cleared
        report "Phase 3: Turn 2 (P_B) JOKER1 CONFIRM" severity note;
        press(btn_joker1);  wait_cycles(2);
        press(btn_confirm); wait_cycles(2);

        -- Phase 4: Player A uses Joker 1 -> max_tk rerolled; both j1 flags now 0
        report "Phase 4: Turn 3 (P_A) JOKER1 CONFIRM" severity note;
        press(btn_joker1);  wait_cycles(2);
        press(btn_confirm); wait_cycles(2);

        -- Phase 5: Player B uses Joker 2 -> sticks +/-1..4; j2 flag for P_B cleared
        report "Phase 5: Turn 4 (P_B) JOKER2 CONFIRM" severity note;
        press(btn_joker2);  wait_cycles(2);
        press(btn_confirm); wait_cycles(2);

        -- Phase 6: Player A uses Joker 2 -> all four joker flags now 0
        report "Phase 6: Turn 5 (P_A) JOKER2 CONFIRM" severity note;
        press(btn_joker2);  wait_cycles(2);
        press(btn_confirm); wait_cycles(2);

        -- Phase 7: Player B tries Joker 1 again (already used -> ignored)
        report "Phase 7: Turn 6 (P_B) JOKER1 re-press (no effect)" severity note;
        press(btn_joker1);  wait_cycles(1);
        press(btn_confirm); wait_cycles(2);

        -- Phase 8: grind remaining sticks with max takes until S_WIN
        -- extra presses after S_WIN are silently ignored
        report "Phase 8: grinding to S_WIN" severity note;
        for turn in 1 to 15 loop
            press(btn_up);      wait_cycles(1);
            press(btn_up);      wait_cycles(1);
            press(btn_confirm); wait_cycles(2);
        end loop;

        -- Phase 9: observe winner LED blinking, then press Start to go to S_IDLE
        report "Phase 9: S_WIN - observe blink, then START" severity note;
        wait_cycles(8);
        press(btn_start);
        wait_cycles(3);

        -- Phase 10: second game START -> verify joker flags reset (led_j1 should go high)
        report "Phase 10: second START - verify joker reset" severity note;
        press(btn_start);
        wait_cycles(3);
        press(btn_joker1);  wait_cycles(2);
        press(btn_confirm); wait_cycles(2);

        report "Simulation complete" severity note;
        -- stop(0) terminates cleanly so Questa exits with status 0
        stop(0);

    end process;

end architecture sim;
