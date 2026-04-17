-- ///
-- file : nim_fsm.vhd
--
-- Main purpose : game state machine. controls stick count, turn order,
--               player selection, and joker effects. clocked by clk1.
--
-- Input  : clk1    -- game clock (0.7-48 Hz)
--          rnd     -- 7-bit random value from nim_sr (sr_cnt wire)
--          db_edge -- one-cycle button pulses from nim_debounce
--
-- Output : sticks  -- remaining stick count
--          max_tk  -- max sticks the active player may take this turn
--          sel     -- current player selection (1..max_tk)
--          player  -- active player (0=P1, 1=P2)
--          winner  -- winning player after game ends
--          state   -- current FSM state (S_IDLE, S_PLAY, S_WIN)
--          j1_av   -- joker 1 still available for active player
--          j2_av   -- joker 2 still available for active player
-- ///

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.nim_pkg.ALL;

entity nim_fsm is
    port (
        clk1    : in  std_logic;
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

            -- Snapshot joker flags into variables so they can be read and cleared
            -- in the same cycle without a register pipeline delay
            if player_r = '0' then j1_av_v := j1_p1; j2_av_v := j2_p1;
            else                   j1_av_v := j1_p2; j2_av_v := j2_p2;
            end if;

            case state_r is

            when S_IDLE =>
                if db_edge(B_START) = '1' then
                    -- rnd(0) picks the first player randomly at press time
                    player_r <= rnd(0);
                    sticks_r <= to_unsigned(21, 6);
                    max_tk_r <= to_unsigned(3, 4);
                    sel_r    <= to_unsigned(1, 4);
                    -- reset all four joker flags so each player starts with both jokers
                    j1_p1 <= '1'; j1_p2 <= '1';
                    j2_p1 <= '1'; j2_p2 <= '1';
                    state_r  <= S_PLAY;
                end if;

            when S_PLAY =>

                if db_edge(B_UP) = '1' then
                    -- increment sel up to max_tk
                    if sel_r < max_tk_r then sel_r <= sel_r + 1; end if;

                elsif db_edge(B_DOWN) = '1' then
                    -- decrement sel down to minimum of 1
                    if sel_r > 1 then sel_r <= sel_r - 1; end if;

                elsif db_edge(B_JOKER1) = '1' and j1_av_v = '1' then
                    -- reroll max_tk to 2..9 using rnd(2:0), clamp sel if now too high
                    nm       := resize(unsigned(rnd(2 downto 0)), 4) + 2;
                    max_tk_r <= nm;
                    if sel_r > nm then sel_r <= nm; end if;
                    -- mark joker 1 as spent for this player
                    if player_r = '0' then j1_p1 <= '0'; else j1_p2 <= '0'; end if;

                elsif db_edge(B_JOKER2) = '1' and j2_av_v = '1' then
                    -- rnd(3)=0 adds, rnd(3)=1 removes; amount = rnd(1:0)+1 = 1..4
                    delta := resize(unsigned(rnd(1 downto 0)), 3) + 1;
                    if rnd(3) = '0' then
                        ns_v := sticks_r + resize(delta, 6);
                    else
                        -- clamp removal so sticks never drops below 1
                        if sticks_r > resize(delta, 6) then
                            ns_v := sticks_r - resize(delta, 6);
                        else
                            ns_v := to_unsigned(1, 6);
                        end if;
                    end if;
                    sticks_r <= ns_v;
                    -- clamp sel to new sticks count if needed
                    if resize(sel_r, 6) > ns_v then sel_r <= ns_v(3 downto 0); end if;
                    -- mark joker 2 as spent for this player
                    if player_r = '0' then j2_p1 <= '0'; else j2_p2 <= '0'; end if;

                elsif db_edge(B_CONFIRM) = '1' then
                    if sticks_r <= resize(sel_r, 6) then
                        -- current player takes the last stick and LOSES (misere rule).
                        -- flip player_r first so winner = player_r points to the other player
                        player_r <= not player_r;
                        state_r  <= S_WIN;
                    else
                        -- normal turn: subtract sel, reset sel to 1, pass turn
                        sticks_r <= sticks_r - resize(sel_r, 6);
                        sel_r    <= to_unsigned(1, 4);
                        player_r <= not player_r;
                    end if;

                end if;

            when S_WIN =>
                -- wait in S_WIN until Start is pressed; then return to IDLE for setup
                if db_edge(B_START) = '1' then state_r <= S_IDLE; end if;

            end case;
        end if;
    end process;

end rtl;
