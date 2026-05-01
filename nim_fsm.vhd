-- ///
-- file : nim_fsm.vhd
--
-- Main purpose : game state machine for two-player Nim. controls stick count,
--               	turn order, player selection, joker effects, and synchronous
--               	reset. clocked by clk1. We choose the slow clock deliberately
--						to have a more "human feeling" when playing 
--
-- Input  : clk1    -- game clock (0.7-48 Hz)
--          rst     -- synchronous reset (active-high): returns to S_IDLE
--          rnd     -- 7-bit snapshot of sr_cnt (free-running at clk0 speed)
--          db_edge -- one-cycle button pulses from nim_debounce (on PRESS)
--          db_fall -- one-cycle button pulses from nim_debounce (on RELEASE)
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
-- Randomness : rnd is sampled at the exact clk1 cycle that db_edge fires.
--   				 sr_cnt free-runs at clk0 (59-320 Hz) through 0-127, so its value at
--   				 any human-initiated event is unpredictable.
--
--   On START  : rnd(0)     picks first player; rnd(4:0)+9 sets sticks (9-40)
--   On JOKER1 : rnd(2:0)+4 rerolls max_tk to 4-9 (fires on button RELEASE)
--              overflow guard: rnd(2)&rnd(1)=11 (would give 10-11) -> saturate 9
--   On JOKER2 : rnd(0) even=add / odd=remove; rnd(4:1) picks amount 1..sel
--              (fires on button RELEASE; subtract floored at 1 stick)
--
-- Edge detection :
--   db_edge : fires on button PRESS  (raw 0->1) -- used for UP/DOWN/CONFIRM/START
--   db_fall : fires on button RELEASE (raw 1->0) -- used for JOKER1/JOKER2 only
--
-- Edge cases :
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
        rst     : in  std_logic;
        rnd     : in  std_logic_vector(6 downto 0);
        db_edge : in  std_logic_vector(5 downto 0);   -- press pulses
        db_fall : in  std_logic_vector(5 downto 0);   -- release pulses (jokers)

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


    -- Game registers (all clocked by clk1)
    signal sticks_r    : unsigned(5 downto 0) := (others => '0');   -- sticks remaining in the pile
    signal max_take_r  : unsigned(3 downto 0) := to_unsigned(4, 4); -- max sticks allowed per turn (overwritten by random but default is 4)
    signal selection_r : unsigned(3 downto 0) := to_unsigned(1, 4); -- active player's chosen amount (1..max_take)

    -- Turn and state tracking
    signal player_r : std_logic := '0';   -- active player: '0'=P1, '1'=P2
    signal state_r  : state_t   := S_IDLE;


    -- Joker availability flags
    signal joker1_p1 : std_logic := '1';   -- P1's Joker 1 (reroll max_take to 4-9)
    signal joker1_p2 : std_logic := '1';   -- P2's Joker 1
    signal joker2_p1 : std_logic := '1';   -- P1's Joker 2 (add or remove sticks)
    signal joker2_p2 : std_logic := '1';   -- P2's Joker 2

begin


    -- Output wiring: 

    sticks <= sticks_r;
    max_tk <= max_take_r;
    sel    <= selection_r;
    player <= player_r;
    state  <= state_r;

    -- player_r is flipped just before entering S_WIN, so it already holds the winner
	 
    winner <= player_r;

    -- Expose only the active player's joker flags (the other player's are irrelevant)
	 
    j1_av <= joker1_p1 when player_r = '0' else joker1_p2;
    j2_av <= joker2_p1 when player_r = '0' else joker2_p2;


    process(clk1)
        -- Local snapshots of the active player's joker flags.
        -- Using variables avoids the one-cycle lag 
		  
        variable joker1_avail : std_logic;
        variable joker2_avail : std_logic;
        -- Joker 2: number of sticks to add or remove this activation
		  
        variable stick_delta  : unsigned(3 downto 0);
        -- Joker 1: candidate new max_take value (checked for overflow before storing)
		  
        variable new_max      : unsigned(3 downto 0);
    begin
        if rising_edge(clk1) then

            -- Synchronous reset: highest priority, active from any state.
            -- Only state_r and player_r are reset because all other values are overwritten
				
            if rst = '1' then
                state_r  <= S_IDLE;
                player_r <= '0';

            else

                -- Snapshot the active player's joker flags
					 
                if player_r = '0' then
                    joker1_avail := joker1_p1;
                    joker2_avail := joker2_p1;
                else
                    joker1_avail := joker1_p2;
                    joker2_avail := joker2_p2;
                end if;

                case state_r is

                -- _____________________________________________________________
                when S_IDLE =>
                -- Waiting for START.
                -- _____________________________________________________________

                    if db_edge(B_START) = '1' then
                        -- Sample rnd at the exact cycle START is pressed.
                        -- sr_cnt free-runs at clk0 through 0-127, so its value
                        -- is unpredictable to the player at human reaction time.
								
                        player_r    <= rnd(0);                                    -- rnd(0): 0=P1 goes first, 1=P2 goes first
                        sticks_r    <= resize(unsigned(rnd(4 downto 0)), 6) + 9;  -- rnd(4:0)+9 gives 9-40 sticks
								
                        if rnd(2) = '1' and rnd(1) = '1' then
									max_take_r <= to_unsigned(9, 4);       -- overflow guard: saturate to 9
								else
										  max_take_r <= resize(unsigned(rnd(2 downto 0)), 4) + 4;  -- 4-9
								end if;
								
                        selection_r <= to_unsigned(1, 4);                         -- selection starts at 1
                        -- Restore all four joker flags for the new game
								
                        joker1_p1 <= '1';  joker1_p2 <= '1';
                        joker2_p1 <= '1';  joker2_p2 <= '1';
                        state_r   <= S_PLAY;
                    end if;

                -- _____________________________________________________________
                when S_PLAY =>
                -- Active game: players alternate turns selecting and taking sticks.
                -- Button priority (highest first): UP > DOWN > JOKER1 > JOKER2 > CONFIRM
                -- _____________________________________________________________

                    if db_edge(B_UP) = '1' then
                        -- Increase selection by 1, capped at max_take
								
                        if selection_r < max_take_r then
                            selection_r <= selection_r + 1;
                        end if;

                    elsif db_edge(B_DOWN) = '1' then
                        -- Decrease selection by 1, floored at 1 (must take at least one stick)
								
                        if selection_r > 1 then
                            selection_r <= selection_r - 1;
                        end if;

                    elsif db_fall(B_JOKER1) = '1' and joker1_avail = '1' then
                        -- JOKER 1: reroll max_take to a random value in [4, 9].
                        -- Fires on button RELEASE for better randomness.
                        --
                        -- Implementation: rnd(2:0)+4 maps rnd values 0-7 to 4-11.
                        -- Values 6 and 7 (rnd(2)='1' AND rnd(1)='1') would give 10 or
                        -- 11, so they are detected and saturated
								
                        if rnd(2) = '1' and rnd(1) = '1' then
                            new_max := to_unsigned(9, 4);           -- overflow: saturate to 9
                        else
                            new_max := resize(unsigned(rnd(2 downto 0)), 4) + 4;  -- normal: 4-9
                        end if;
                        max_take_r <= new_max;
                        -- Pull selection down if it now exceeds the new maximum
								
                        if selection_r > new_max then
                            selection_r <= new_max;
                        end if;
                        -- Mark Joker 1 as spent for the active player
								
                        if player_r = '0' then joker1_p1 <= '0'; else joker1_p2 <= '0'; end if;

                    elsif db_fall(B_JOKER2) = '1' and joker2_avail = '1' then
                        -- JOKER 2: randomly add or remove sticks from the pile.
                        -- Fires on button RELEASE for better randomness.
                        --
                        -- Direction : rnd(0)=0 -> add sticks, rnd(0)=1 -> remove sticks (50/50).
								--
                        -- Amount    : rnd(4:1) clamped to [1, selection_r].
                        --   If rnd(4:1) < selection_r : stick_delta = rnd(4:1)+1  (gives 1..selection_r)
                        --   Otherwise                 : stick_delta = selection_r  (full clamp)
								
                        if unsigned(rnd(4 downto 1)) < resize(selection_r, 4) then
                            stick_delta := resize(unsigned(rnd(4 downto 1)), 4) + 1;
                        else
                            stick_delta := selection_r;
                        end if;

                        if rnd(0) = '0' then
                            -- Even rnd(0): add sticks to the pile
									 
                            sticks_r <= sticks_r + resize(stick_delta, 6);
                        else
                            -- Odd rnd(0): remove sticks, floored at 1 (pile can never empty via joker)
									 
                            if sticks_r > resize(stick_delta, 6) then
                                sticks_r <= sticks_r - resize(stick_delta, 6);
                            else
                                sticks_r <= to_unsigned(1, 6);
                            end if;
                        end if;
                        -- Reset selection to 1 to keep the 7-segment display consistent.
								
                        selection_r <= to_unsigned(1, 4);
                        -- Mark Joker 2 as spent for the active player
								
                        if player_r = '0' then joker2_p1 <= '0'; else joker2_p2 <= '0'; end if;

                    elsif db_edge(B_CONFIRM) = '1' then
                        -- Confirm the current selection and end the active player's turn.
                        -- db_edge is a one-cycle pulse: holding CONFIRM does not retrigger.
								
                        if sticks_r <= resize(selection_r, 6) then
                            -- the player who takes the last stick(s) LOSES.
                            -- Flip player_r before entering S_WIN so winner is already set.
									 
                            player_r <= not player_r;
                            state_r  <= S_WIN;
                        else
                            -- Normal turn: subtract selection, reset selection to 1, swap player
									 
                            sticks_r    <= sticks_r - resize(selection_r, 6);
                            selection_r <= to_unsigned(1, 4);
                            player_r    <= not player_r;
                        end if;

                    end if;

                -- _____________________________________________________________
                when S_WIN =>
                -- Game over. Winner LEDs held until START is pressed for a new game.
                -- _____________________________________________________________

                    if db_edge(B_START) = '1' then
                        state_r <= S_IDLE;
                    end if;

                end case;

            end if;
				
        end if;
		  
    end process;

end rtl;
