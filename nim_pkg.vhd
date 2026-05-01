-- ///
-- file : nim_pkg.vhd
--
-- Main purpose : shared types and constants used by all other files.
-- ///

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package nim_pkg is

    -- Game state machine states:
    --   S_IDLE : waiting for a player to press START (both player LEDs on and carroussel working)
    --   S_PLAY : game in progress, players alternate turns
    --   S_WIN  : game over, winner displayed by blinking; press START to play again
    type state_t is (S_IDLE, S_PLAY, S_WIN);

    -- Bit positions within the 6-bit button vectors (db_edge / db_fall / raw).
	 -- Be Careful to assign this way in other files or it won't work : 
	 --
    --   btn_raw <= (not btn_down) & (not btn_up) & (not btn_confirm) &
    --              (not btn_joker2) & (not btn_joker1) & (not btn_start)
    constant B_START   : integer := 0;   -- begin or restart a game
    constant B_JOKER1  : integer := 1;   -- reroll max sticks per turn (4-9); fires on release
    constant B_JOKER2  : integer := 2;   -- add or remove sticks randomly; fires on release
    constant B_CONFIRM : integer := 3;   -- lock in the current selection and end the turn
    constant B_UP      : integer := 4;   -- increment the stick selection by 1
    constant B_DOWN    : integer := 5;   -- decrement the stick selection by 1

end package;
