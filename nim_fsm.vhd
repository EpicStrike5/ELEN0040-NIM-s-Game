-- ///
-- file : nim_fsm.vhd
--
-- Main purpose : game state machine for two-player Nim. controls stick count,
--               turn order, player selection, joker effects, and synchronous
--               reset. clocked by clk1.
--
-- Input  : clk1    -- game clock (0.7-48 Hz)
--          rst     -- synchronous reset (active-high): returns to S_IDLE
--          rnd     -- 7-bit snapshot of sr_cnt (free-running at clk0 speed)
--          db_edge -- one-cycle button pulses from nim_debounce
--
-- Output : sticks  -- remaining stick count
--          max_tk  -- max sticks the active player may take this turn
--          sel     -- current player selection (1..max_tk)
--          player  -- whose turn it is (0=P1, 1=P2)
--          winner  -- winning player after game ends
--          state   -- current FSM state (S_IDLE, S_PLAY, S_WIN)
--          j1_av   -- joker 1 still available for the active player
--          j2_av   -- joker 2 still available for the active player
--
-- Randomness: rnd is sampled at the exact clk1 cycle that db_edge fires.
--   sr_cnt free-runs at clk0 (59-320 Hz) through 0-127, so its value at
--   any human-initiated event is unpredictable.
--   On START: rnd(0) picks first player; rnd(4:0)+9 sets sticks (9-40).
--   On JOKER1: rnd(2:0) rerolls max_tk (2-9).
--   On JOKER2: rnd(3) picks add/remove; rnd(1:0) picks amount (1-4).
--
-- Edge cases:
--   Hold CONFIRM : db_edge is a one-cycle pulse; holding does not retrigger.
--   Simultaneous : priority UP > DOWN > JOKER1 > JOKER2 > CONFIRM.
-- ///

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.nim_pkg.ALL;

entity nim_fsm is
    port (
        clk1    : in  std_logic;
        rst     : in  std_logic;                      -- synchronous reset (active-high)
        rnd     : in  std_logic_vector(6 downto 0);
        db_edge : in  std_logic_vector(5 downto 0);

        sticks  : out unsigned(5 downto 0);
        max_tk  : out unsigned(3 downto 0);
        sel     : out unsigned(3 downto 0);
        player  : out std_logic;
        winner  : out std_logic;
        state   : out state_t;
        j1_av   : out std_logic;
        j2_av   : out std_logic
    );
end nim_fsm;

architecture rtl of nim_fsm is

    signal sticks_r : unsigned(5 downto 0) := (others => '0');  -- set by START via rnd
    signal max_tk_r : unsigned(3 downto 0) := to_unsigned(3,  4);
    signal sel_r    : unsigned(3 downto 0) := to_unsigned(1,  4);
    signal player_r : std_logic := '0';
    signal state_r  : state_t   := S_IDLE;

    -- One flag per player per joker. '1' = available, '0' = spent.
    -- All four flags reset to '1' on START; cleared individually when a player uses one.
    signal j1_p1 : std_logic := '1';
    signal j1_p2 : std_logic := '1';
    signal j2_p1 : std_logic := '1';
    signal j2_p2 : std_logic := '1';

begin

    sticks <= sticks_r;
    max_tk <= max_tk_r;
    sel    <= sel_r;
    player <= player_r;
    -- player_r is flipped before entering S_WIN, so it already holds the winner
    winner <= player_r;
    state  <= state_r;

    -- Joker availability follows the active player's flag
    j1_av <= j1_p1 when player_r = '0' else j1_p2;
    j2_av <= j2_p1 when player_r = '0' else j2_p2;

    process(clk1)
        variable j1_av_v : std_logic;
        variable j2_av_v : std_logic;
        variable delta   : unsigned(2 downto 0);
        variable ns_v    : unsigned(5 downto 0);
        variable nm      : unsigned(3 downto 0);
    begin
        if rising_edge(clk1) then

            -- Synchronous reset: highest priority, works from any state.
            -- Only state_r and player_r are reset (both target '0', so synthesis
            -- can reuse the macrocell clear pins at zero extra LE cost).
            -- sticks / max_tk / sel / joker flags are untouched: START overwrites them.
            if rst = '1' then
                state_r  <= S_IDLE;
                player_r <= '0';

            else

                -- Snapshot joker flags for the active player
                if player_r = '0' then j1_av_v := j1_p1; j2_av_v := j2_p1;
                else                   j1_av_v := j1_p2; j2_av_v := j2_p2;
                end if;

                case state_r is

                -- -----------------------------------------------------------------
                when S_IDLE =>
                -- -----------------------------------------------------------------
                    if db_edge(B_START) = '1' then
                        -- Snapshot rnd the instant START is pressed.
                        -- sr_cnt free-runs at clk0 through 0-127, so the value
                        -- is unpredictable to the player.
                        player_r <= rnd(0);                                    -- 0=P1, 1=P2
                        sticks_r <= resize(unsigned(rnd(4 downto 0)), 6) + 9;  -- 9-40 sticks
                        max_tk_r <= to_unsigned(3, 4);
                        sel_r    <= to_unsigned(1, 4);
                        j1_p1 <= '1'; j1_p2 <= '1';
                        j2_p1 <= '1'; j2_p2 <= '1';
                        state_r <= S_PLAY;
                    end if;

                -- -----------------------------------------------------------------
                when S_PLAY =>
                -- -----------------------------------------------------------------

                    -- Priority: UP > DOWN > JOKER1 > JOKER2 > CONFIRM.
                    -- Both players are human; player_r tells whose turn it is.

                    if db_edge(B_UP) = '1' then
                        -- increment sel, capped at max_tk
                        if sel_r < max_tk_r then sel_r <= sel_r + 1; end if;

                    elsif db_edge(B_DOWN) = '1' then
                        -- decrement sel, floored at 1
                        if sel_r > 1 then sel_r <= sel_r - 1; end if;

                    elsif db_edge(B_JOKER1) = '1' and j1_av_v = '1' then
                        -- reroll max_tk to 2..9; clamp sel if now too high
                        nm       := resize(unsigned(rnd(2 downto 0)), 4) + 2;
                        max_tk_r <= nm;
                        if sel_r > nm then sel_r <= nm; end if;
                        -- clear the active player's joker-1 flag
                        if player_r = '0' then j1_p1 <= '0'; else j1_p2 <= '0'; end if;

                    elsif db_edge(B_JOKER2) = '1' and j2_av_v = '1' then
                        -- add or remove 1..4 sticks; direction from rnd(3)
                        delta := resize(unsigned(rnd(1 downto 0)), 3) + 1;
                        if rnd(3) = '0' then
                            ns_v := sticks_r + resize(delta, 6);
                        else
                            if sticks_r > resize(delta, 6) then
                                ns_v := sticks_r - resize(delta, 6);
                            else
                                ns_v := to_unsigned(1, 6);
                            end if;
                        end if;
                        sticks_r <= ns_v;
                        if resize(sel_r, 6) > ns_v then sel_r <= ns_v(3 downto 0); end if;
                        -- clear the active player's joker-2 flag
                        if player_r = '0' then j2_p1 <= '0'; else j2_p2 <= '0'; end if;

                    elsif db_edge(B_CONFIRM) = '1' then
                        -- human confirm: single-cycle pulse from nim_debounce
                        -- (holding CONFIRM does not re-fire)
                        if sticks_r <= resize(sel_r, 6) then
                            -- last stick(s) taken → misère: flip player then go to WIN
                            player_r <= not player_r;
                            state_r  <= S_WIN;
                        else
                            -- normal turn: remove sticks, reset sel to 1, swap player
                            sticks_r <= sticks_r - resize(sel_r, 6);
                            sel_r    <= to_unsigned(1, 4);
                            player_r <= not player_r;
                        end if;

                    end if;

                -- -----------------------------------------------------------------
                when S_WIN =>
                -- -----------------------------------------------------------------
                    -- wait for Start to return to IDLE for a new game
                    if db_edge(B_START) = '1' then state_r <= S_IDLE; end if;

                end case;
            end if;
        end if;
    end process;

end rtl;
