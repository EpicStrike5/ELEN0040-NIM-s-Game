-- ///
-- file : nim_fsm.vhd
--
-- Main purpose : game state machine. controls stick count, turn order,
--               player selection, joker effects, synchronous reset, and
--               an auto-playing bot for player 2. clocked by clk1.
--
-- Input  : clk1    -- game clock (0.7-48 Hz)
--          rst     -- synchronous reset: returns to S_IDLE from any state
--          rnd     -- 7-bit random value from nim_sr (sr_cnt wire)
--          db_edge -- one-cycle button pulses from nim_debounce
--
-- Output : sticks  -- remaining stick count
--          max_tk  -- max sticks the active player may take this turn
--          sel     -- current player selection (1..max_tk)
--          player  -- active player (0=P1/human, 1=P2/bot)
--          winner  -- winning player after game ends
--          state   -- current FSM state (S_IDLE, S_PLAY, S_WIN)
--          j1_av   -- joker 1 still available for active player
--          j2_av   -- joker 2 still available for active player
--
-- Bot (P2): acts on the first clk1 cycle of its turn (no delay counter —
--   removed to stay within 160 LEs). Takes a random amount 1..min(4, max_tk).
--   Bot and human confirm share ONE comparator + subtractor via eff_sel mux.
--   Bot never uses jokers; j1_p2 / j2_p2 remain '1' for the whole game.
--
-- Edge cases handled:
--   Hold CONFIRM : db_edge is a single-cycle pulse from nim_debounce;
--                  holding the button only fires the FSM once. (by design)
--   Simultaneous : priority is UP > DOWN > JOKER1 > JOKER2 > CONFIRM.
--                  Each human-button condition guards with `player_r='0'`
--                  so the bot's auto-confirm at the bottom is never blocked.
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

    signal sticks_r : unsigned(5 downto 0) := to_unsigned(21, 6);
    signal max_tk_r : unsigned(3 downto 0) := to_unsigned(3,  4);
    signal sel_r    : unsigned(3 downto 0) := to_unsigned(1,  4);
    signal player_r : std_logic := '0';
    signal state_r  : state_t   := S_IDLE;

    -- One flag per player per joker. '1' = available, '0' = spent.
    -- j1_p2 / j2_p2 are reset on START but never cleared (bot does not use jokers).
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
        -- eff_sel: shared input to the confirm comparator/subtractor.
        -- bot (player_r='1') uses a random 1..min(4,max_tk);
        -- human (player_r='0') uses sel_r.
        -- Having ONE variable here lets synthesis build ONE comparator and
        -- ONE subtractor for both paths instead of duplicating them.
        variable eff_sel : unsigned(3 downto 0);
        variable bot_take : unsigned(3 downto 0);
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
                        -- rnd(0) picks the first player randomly at press time
                        player_r <= rnd(0);
                        sticks_r <= to_unsigned(21, 6);
                        max_tk_r <= to_unsigned(3, 4);
                        sel_r    <= to_unsigned(1, 4);
                        -- reset all four joker flags for a fresh game
                        j1_p1 <= '1'; j1_p2 <= '1';
                        j2_p1 <= '1'; j2_p2 <= '1';
                        state_r <= S_PLAY;
                    end if;

                -- -----------------------------------------------------------------
                when S_PLAY =>
                -- -----------------------------------------------------------------

                    -- Compute bot's random take: rnd(1:0)+1 = 1..4, clamped to max_tk.
                    -- This variable is only used when player_r='1'; synthesis discards
                    -- it for the player_r='0' path.
                    bot_take := resize(unsigned(rnd(1 downto 0)), 4) + 1;
                    if bot_take > max_tk_r then bot_take := max_tk_r; end if;

                    -- eff_sel selects between bot's random take and the human's
                    -- current selection. ONE comparator and ONE subtractor below
                    -- serve both, minimising logic duplication.
                    if player_r = '1' then eff_sel := bot_take;
                    else                   eff_sel := sel_r;
                    end if;

                    -- Priority: UP > DOWN > JOKER1 > JOKER2 > CONFIRM / BOT-AUTO.
                    -- Every human-button condition includes `player_r = '0'` so that
                    -- when it is the bot's turn (player_r='1') all human branches are
                    -- skipped and control falls through to the shared confirm path.

                    if player_r = '0' and db_edge(B_UP) = '1' then
                        -- increment sel, capped at max_tk
                        if sel_r < max_tk_r then sel_r <= sel_r + 1; end if;

                    elsif player_r = '0' and db_edge(B_DOWN) = '1' then
                        -- decrement sel, floored at 1
                        if sel_r > 1 then sel_r <= sel_r - 1; end if;

                    elsif player_r = '0' and db_edge(B_JOKER1) = '1' and j1_av_v = '1' then
                        -- reroll max_tk to 2..9; clamp sel if now too high
                        nm       := resize(unsigned(rnd(2 downto 0)), 4) + 2;
                        max_tk_r <= nm;
                        if sel_r > nm then sel_r <= nm; end if;
                        -- player_r='0' guaranteed in this branch, so only P1's flag
                        j1_p1 <= '0';

                    elsif player_r = '0' and db_edge(B_JOKER2) = '1' and j2_av_v = '1' then
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
                        -- player_r='0' guaranteed; only P1's flag
                        j2_p1 <= '0';

                    -- Shared confirm path:
                    --   bot   : player_r='1' → fires automatically every cycle of its turn
                    --   human : player_r='0' and B_CONFIRM pressed (single-cycle db_edge pulse;
                    --           holding CONFIRM does NOT re-fire thanks to nim_debounce)
                    elsif player_r = '1' or db_edge(B_CONFIRM) = '1' then
                        if sticks_r <= resize(eff_sel, 6) then
                            -- last stick(s) taken → misère: flip player then go to WIN
                            player_r <= not player_r;
                            state_r  <= S_WIN;
                        else
                            -- normal turn: remove sticks, reset sel to 1, swap player
                            sticks_r <= sticks_r - resize(eff_sel, 6);
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
