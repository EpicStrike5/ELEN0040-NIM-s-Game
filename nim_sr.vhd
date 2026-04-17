-- ///
-- file : nim_sr.vhd
--
-- Main purpose : drive the 5x TLC6C598 daisy-chained shift registers
--               that control the 40 stick LEDs. also exposes a free-running
--               counter as a cheap random source for the FSM.
--
-- Input  : clk0   -- 59-320 Hz serialiser clock (set once via potentiometer)
--          sticks -- number of remaining sticks (from FSM)
--
-- Output : sr_data  -- serial data to first TLC6C598
--          sr_clk   -- shift clock to all TLC6C598
--          sr_latch -- latch pulse (one clk0 cycle wide) after full frame
--          sr_rnd   -- 7-bit random value (sr_cnt wire, zero extra LEs)
-- ///

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity nim_sr is
    port (
        clk0     : in  std_logic;
        sticks   : in  unsigned(5 downto 0);
        sr_data  : out std_logic;
        sr_clk   : out std_logic;
        sr_latch : out std_logic;
        sr_rnd   : out std_logic_vector(6 downto 0)
    );
end nim_sr;

architecture rtl of nim_sr is

    signal sr_cnt : unsigned(6 downto 0) := (others => '0');

    -- LED k lights when k < sticks. IC1 DRAIN0 = LED 0 (last bit shifted out),
    -- so bit index idx corresponds to LED (39-idx). Returns '1' when (39-idx) < sticks.
    function led_bit(idx  : unsigned(5 downto 0);
                     n_st : unsigned(5 downto 0)) return std_logic is
    begin
        if (to_unsigned(39, 6) - idx) < n_st then return '1'; else return '0'; end if;
    end function;

begin

    -- sr_rnd is a pure wire: no extra logic, just exposes the counter value
    sr_rnd <= std_logic_vector(sr_cnt);

    process(clk0)
    begin
        if rising_edge(clk0) then

            sr_latch <= '0';

            if sr_cnt < 80 then
                -- steps 0-79: two steps per bit (even=data+clk-low, odd=clk-high)
                if sr_cnt(0) = '0' then
                    sr_clk  <= '0';
                    sr_data <= led_bit(sr_cnt(6 downto 1), sticks);
                else
                    sr_clk  <= '1';
                end if;
                sr_cnt <= sr_cnt + 1;

            elsif sr_cnt = 80 then
                -- step 80: all 40 bits shifted; pulse latch to push data to outputs
                sr_clk   <= '0';
                sr_latch <= '1';
                sr_cnt   <= sr_cnt + 1;

            else
                -- step 81: reset counter to start next frame
                sr_cnt <= (others => '0');
            end if;

        end if;
    end process;

end rtl;
