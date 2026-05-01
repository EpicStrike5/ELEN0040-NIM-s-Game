-- ///
-- file : nim_sr.vhd
--
-- Main purpose : drive the 5x TLC6C598 daisy-chained shift registers that
--               	control the 40 stick LEDs. also exposes the internal counter
--               	as a free-running random source for the FSM.
--						This random was recommended by the teacher and cost way less than a LFSR
--
-- Input  : clk0   -- 59-320 Hz serialiser clock. Internal 555 timer wired to PIN7
--          sticks -- number of LEDs to light (remaining sticks, or idle animation value)
--
-- Output : sr_data  -- serial data line to the first TLC6C598
--          sr_clk   -- shift clock shared by all TLC6C598s in the chain
--          sr_latch -- latch pulse (one clk0 cycle wide) after each complete 40-bit frame
--          sr_rnd   -- 7-bit random value; a direct wire to sr_cnt. 
--
-- Frame timing (sr_cnt 0 -> 127, natural 7-bit overflow):
--   Steps   0-79  : transmit 40 bits, 2 clk0 cycles per bit
--                   even step : place data bit on sr_data, hold sr_clk low
--                   odd  step : raise sr_clk to clock the bit into the chain
--							see datasheet for more information on the timing sequence : https://www.ti.com/product/TLC6C598
--   Step    80    : all 40 bits shifted; pulse sr_latch to push the frame to LED outputs. Since "G" is pulled low then we always make the latch visible.
--   Steps 81-127  : idle; sr_cnt continues counting so the random period stays full (128 cycles)
--
-- LED mapping : 	IC1 DRAIN0 drives LED 0 (the last bit shifted out).
--   					led_bit(bit_idx, num_sticks) returns '1' when LED (39-bit_idx) should be on,
--   					i.e. when its position index is less than the stick count.
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

    -- Free-running 7-bit counter: drives the serialisation state machine AND
    -- serves as the random source. act as "wire" in this case.
    signal sr_cnt : unsigned(6 downto 0) := (others => '0');

    -- Returns whether LED (39 - bit_idx) should be lit given num_sticks remaining.
    -- IC1 DRAIN0 = LED 0 = last bit shifted out, so the bit at position bit_idx
    -- in the serial stream corresponds to physical LED (39 - bit_idx).
    -- The LED is on when its physical index is strictly less than num_sticks.
    function led_bit(bit_idx   : unsigned(5 downto 0);
                     num_sticks : unsigned(5 downto 0)) return std_logic is
    begin
        if (to_unsigned(39, 6) - bit_idx) < num_sticks then
            return '1';
        else
            return '0';
        end if;
    end function;

begin

    -- Expose the counter value directly as random bits.
    sr_rnd <= std_logic_vector(sr_cnt);

    process(clk0)
    begin
        if rising_edge(clk0) then

            -- Default: keep latch low (will be overridden on step 80 only)
            sr_latch <= '0';

            if sr_cnt < 80 then
                -- Serialisation phase: 2 clk0 cycles per bit, 40 bits total (steps 0-79).
                -- sr_cnt(0) distinguishes the two half-cycles within each bit slot:
                --   even (sr_cnt(0)=0): present the data bit, keep sr_clk low
                --   odd  (sr_cnt(0)=1): raise sr_clk to clock the bit into the chain
                -- The bit index within the 40-bit frame is sr_cnt(6 downto 1).
                if sr_cnt(0) = '0' then
                    sr_clk  <= '0';
                    sr_data <= led_bit(sr_cnt(6 downto 1), sticks);
                else
                    sr_clk  <= '1';
                end if;
                sr_cnt <= sr_cnt + 1;

            elsif sr_cnt = 80 then
                -- Latch phase: all 40 bits are in the chain according to how they are supposed to be lit
					 -- pulse sr_latch to transfer to the output latches and illuminate the corresponding LEDs.

                sr_clk   <= '0';
                sr_latch <= '1';
                sr_cnt   <= sr_cnt + 1;

            else
                -- Idle phase (steps 81-127): no serial activity.
                -- sr_cnt keeps incrementing and wraps naturally at 127->0,
                -- maintaining a full 128-cycle period for the random source.
                sr_cnt <= sr_cnt + 1;

            end if;

        end if;
    end process;

end rtl;
