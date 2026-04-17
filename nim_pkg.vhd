-- ///
-- file : nim_pkg.vhd
--
-- Main purpose : shared types and constants used by all other files.
--                must be compiled first.
--
-- Input  : none
--
-- Output : state_t type (S_IDLE, S_PLAY, S_WIN)
--          button index constants B_START .. B_DOWN
-- ///

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package nim_pkg is

    type state_t is (S_IDLE, S_PLAY, S_WIN);

    constant B_START   : integer := 0;
    constant B_JOKER1  : integer := 1;
    constant B_JOKER2  : integer := 2;
    constant B_CONFIRM : integer := 3;
    constant B_UP      : integer := 4;
    constant B_DOWN    : integer := 5;

end package;
