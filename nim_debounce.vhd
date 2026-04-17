-- ///
-- file : nim_debounce.vhd
--
-- Main purpose : detect one rising-edge pulse per button press for all 6 buttons.
--               hardware RC filter (10k + 100nF) removes fast glitches before
--               the signal reaches the CPLD; this block handles edge detection only.
--
-- Input  : clk1  -- game clock (0.7-48 Hz); period >> bounce duration (~1-5 ms)
--          raw   -- active-high button states (6 bits)
--
-- Output : db_edge -- one-cycle high pulse per press, one bit per button
-- ///

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity nim_debounce is
    port (
        clk1    : in  std_logic;
        raw     : in  std_logic_vector(5 downto 0);  -- active-high button inputs
        db_edge : out std_logic_vector(5 downto 0)   -- one-cycle pulse per press
    );
end nim_debounce;

architecture rtl of nim_debounce is
    signal prev_raw : std_logic_vector(5 downto 0) := (others => '0');
begin

    -- prev_raw latches raw every cycle so we can compare consecutive states
    process(clk1)
    begin
        if rising_edge(clk1) then
            prev_raw <= raw;
        end if;
    end process;

    -- db_edge is '1' only on the cycle where raw went 0->1 (rising edge)
    db_edge <= raw and not prev_raw;

end rtl;
