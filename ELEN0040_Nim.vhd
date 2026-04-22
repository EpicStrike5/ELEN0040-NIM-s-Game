-- ///
-- file : ELEN0040_Nim.vhd
--
-- Main purpose : top-level for the Nim game on Intel MAX V 5M160ZE64C4.
--               instantiates nim_debounce, nim_sr, and nim_fsm; wires all
--               I/O signals; drives LEDs and BCD outputs.
--
-- Input  : clk0        -- 59-320 Hz (LMC555, set via potentiometer)
--          clk1        -- 0.7-48 Hz (LMC555, set via potentiometer)
--          btn_*       -- active-low buttons (10k pull-up to VCCIO, pressed = GND)
--          btn_reset   -- active-low reset (same RC pull-up); returns to S_IDLE
--                         from any game state without needing to finish the game
--
-- Output : sr_data / sr_clk / sr_latch -- TLC6C598 chain (40 stick LEDs)
--          bcd_max_tk  -- 4-bit BCD to CD4511 #1 (max sticks per turn)
--          bcd_sel     -- 4-bit BCD to CD4511 #2 (current selection)
--          led_p1      -- player 1 LED (both on=IDLE, active on=PLAY, blink=WIN)
--          led_p2      -- player 2 / bot LED
--          led_j1      -- joker 1 available for active human player
--          led_j2      -- joker 2 available for active human player
--
-- Carousel : in S_IDLE the SR chain shows a fill animation instead of static
--            sticks. anim_r is a plain 6-bit up-counter (0→63 natural overflow)
--            driven by clk1: 0-40 LEDs fill up; 41-63 all 40 LEDs on (hold);
--            snap dark at the 63→0 wrap, then repeat.
--            Counter + mux ≈ 14 LEs (no direction bit, no comparators).
--
-- Two-player : both P1 and P2 are human; player_r in nim_fsm tracks whose
--              turn it is. Both players share the same physical buttons.
-- ///

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.nim_pkg.ALL;

entity ELEN0040_Nim is
    port (
        clk0        : in  std_logic;
        clk1        : in  std_logic;

        -- active-low: 10k pull-up to VCCIO, button shorts to GND
        btn_start   : in  std_logic;
        btn_joker1  : in  std_logic;
        btn_joker2  : in  std_logic;
        btn_confirm : in  std_logic;
        btn_up      : in  std_logic;
        btn_down    : in  std_logic;
        btn_reset   : in  std_logic;   -- abort game, return to S_IDLE immediately

        -- TLC6C598 shift register chain (40 stick LEDs)
        sr_data     : out std_logic;
        sr_clk      : out std_logic;
        sr_latch    : out std_logic;

        -- BCD outputs: CD4511 LE pin tied GND (transparent), no VHDL decode needed
        bcd_max_tk  : out std_logic_vector(3 downto 0);
        bcd_sel     : out std_logic_vector(3 downto 0);

        -- Player LEDs: both on=IDLE, one on per turn=PLAY, winner blinks=WIN
        led_p1      : out std_logic;
        led_p2      : out std_logic;

        -- Joker LEDs: on while active human player still has that joker
        led_j1      : out std_logic;
        led_j2      : out std_logic
    );
end ELEN0040_Nim;

architecture rtl of ELEN0040_Nim is

    signal blink_ff  : std_logic := '0';
    signal rst_s     : std_logic;
    signal sr_rnd_s  : std_logic_vector(6 downto 0);
    signal raw_btns  : std_logic_vector(5 downto 0);
    signal db_edge_s : std_logic_vector(5 downto 0);
    signal sticks_s  : unsigned(5 downto 0);
    signal max_tk_s  : unsigned(3 downto 0);
    signal sel_s     : unsigned(3 downto 0);
    signal player_s  : std_logic;
    signal winner_s  : std_logic;
    signal state_s   : state_t;
    signal j1_av_s   : std_logic;
    signal j2_av_s   : std_logic;

    -- carousel: plain 6-bit up-counter (0→63, natural overflow) driven by clk1.
    -- No direction bit and no comparators needed — saves ~19 LEs vs a bounce counter.
    signal anim_r      : unsigned(5 downto 0) := (others => '0');
    signal sr_sticks_s : unsigned(5 downto 0);   -- mux: anim in S_IDLE, sticks_s otherwise

    component nim_debounce is
        port (
            clk1    : in  std_logic;
            raw     : in  std_logic_vector(5 downto 0);
            db_edge : out std_logic_vector(5 downto 0)
        );
    end component;

    component nim_sr is
        port (
            clk0     : in  std_logic;
            sticks   : in  unsigned(5 downto 0);
            sr_data  : out std_logic;
            sr_clk   : out std_logic;
            sr_latch : out std_logic;
            sr_rnd   : out std_logic_vector(6 downto 0)
        );
    end component;

    component nim_fsm is
        port (
            clk1    : in  std_logic;
            rst     : in  std_logic;
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
    end component;

begin

    -- blink_ff toggles every clk1 edge → clk1/2 square wave used for winner LED blink
    process(clk1)
    begin
        if rising_edge(clk1) then
            blink_ff <= not blink_ff;
        end if;
    end process;

    -- ----------------------------------------------------------------
    -- Idle carousel: anim_r counts 0→63 (natural 6-bit overflow) every clk1 tick.
    --   0-40  : 0→40 LEDs light up (fill)
    --   41-63 : all 40 LEDs on      (brief hold — values > 40 saturate the display)
    --   63→0  : snap dark, repeat
    -- Counter resets to 0 when a game is running so IDLE always starts from dark.
    -- ----------------------------------------------------------------
    process(clk1)
    begin
        if rising_edge(clk1) then
            if state_s /= S_IDLE then
                anim_r <= (others => '0');  -- hold at zero during play / win
            else
                anim_r <= anim_r + 1;       -- free-run; 63 overflows to 0 naturally
            end if;
        end if;
    end process;

    -- In S_IDLE feed the carousel value to nim_sr; otherwise show real sticks.
    sr_sticks_s <= anim_r when state_s = S_IDLE else sticks_s;

    -- invert reset button: active-low pin → active-high rst signal for FSM
    rst_s <= not btn_reset;

    -- invert all six game buttons: CPLD sees 0 when pressed, FSM expects active-high
    -- bit order must match nim_pkg constants (B_START=0 .. B_DOWN=5)
    raw_btns <= (not btn_down) & (not btn_up) & (not btn_confirm) &
                (not btn_joker2) & (not btn_joker1) & (not btn_start);

    u_deb : nim_debounce
        port map (
            clk1    => clk1,
            raw     => raw_btns,
            db_edge => db_edge_s
        );

    u_sr : nim_sr
        port map (
            clk0     => clk0,
            sticks   => sr_sticks_s,  -- muxed: carousel in S_IDLE, real sticks otherwise
            sr_data  => sr_data,
            sr_clk   => sr_clk,
            sr_latch => sr_latch,
            sr_rnd   => sr_rnd_s
        );

    u_fsm : nim_fsm
        port map (
            clk1    => clk1,
            rst     => rst_s,
            rnd     => sr_rnd_s,
            db_edge => db_edge_s,
            sticks  => sticks_s,
            max_tk  => max_tk_s,
            sel     => sel_s,
            player  => player_s,
            winner  => winner_s,
            state   => state_s,
            j1_av   => j1_av_s,
            j2_av   => j2_av_s
        );

    -- BCD wires: pure combinational, zero LEs; CD4511 does the segment decoding
    bcd_max_tk <= std_logic_vector(max_tk_s);
    bcd_sel    <= std_logic_vector(sel_s);

    -- led_p1: blinks in WIN if P1 won, on in IDLE, on in PLAY when P1 is active
    led_p1 <= blink_ff     when (state_s = S_WIN  and winner_s = '0') else
              '1'          when  state_s = S_IDLE                      else
              not player_s when  state_s = S_PLAY                      else
              '0';

    -- led_p2: blinks in WIN if P2 won, on in IDLE, on in PLAY when P2 is active
    led_p2 <= blink_ff  when (state_s = S_WIN  and winner_s = '1') else
              '1'        when  state_s = S_IDLE                      else
              player_s   when  state_s = S_PLAY                      else
              '0';

    -- joker LEDs only meaningful during S_PLAY; off in all other states
    led_j1 <= j1_av_s when state_s = S_PLAY else '0';
    led_j2 <= j2_av_s when state_s = S_PLAY else '0';

end rtl;
