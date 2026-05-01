-- ///
-- file : nim_debounce.vhd
--
-- Main purpose : produce one-cycle pulses on both edges of each button for all 6 buttons (we dropped bot button).
--
-- Input  : clk1    -- game clock (0.7-48 Hz); period >> bounce duration (~1-5 ms)
--          raw     -- active-high button states, 1 bit per button (6 total)
--
-- Output : db_edge -- one-cycle high pulse when a button is Pressed (0 -> 1)
--          db_fall -- one-cycle high pulse when a button is Released (1 -> 0)
--
-- Note : 	db_fall is used exclusively for Joker1 and Joker2 since we decided that a button release is more "random" than a button press 
--				since the human cannot really tell whenever the falling condition is from the CPLD perspective. 
-- ///

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity nim_debounce is
    port (
        clk1    : in  std_logic;
        raw     : in  std_logic_vector(5 downto 0);   -- active-high button inputs
        db_edge : out std_logic_vector(5 downto 0);   -- one-cycle pulse on PRESS
        db_fall : out std_logic_vector(5 downto 0)    -- one-cycle pulse on RELEASE
    );
end nim_debounce;

architecture rtl of nim_debounce is

    -- Stores the button state from the previous clk1 cycle.
    -- Comparing btn_prev with raw lets us detect both rising and falling edges. 
	 -- This solves bouncing signal or haptic pressing
    signal btn_prev : std_logic_vector(5 downto 0) := (others => '0');

begin

    -- Capture the current button state every clk1 tick
    process(clk1)
    begin
        if rising_edge(clk1) then
            btn_prev <= raw;
        end if;
    end process;

    -- db_edge: high for exactly one cycle when a button goes from not-pressed to pressed (0->1)
    db_edge <= raw and not btn_prev;

    -- db_fall: high for exactly one cycle when a button goes from pressed to not-pressed (1->0)
    db_fall <= btn_prev and not raw;

end rtl;
