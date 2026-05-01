-- ///
-- file : ELEN0040_Nim.vhd
--
-- Main purpose : top-level for the Nim game
--
-- Input  : clk0        -- 59-320 Hz (LMC555, set via potentiometer)
--          clk1        -- 0.7-48 Hz (LMC555, set via potentiometer)
--          btn_*       -- active-low buttons (10k pull-up to VCCIO, pressed = GND)
--          btn_reset   -- active-low reset; returns to S_IDLE from any game state
--
-- Output : sr_data / sr_clk / sr_latch -- TLC6C598 chain (40 stick LEDs)
--          bcd_max_tk  -- 4-bit BCD to CD4511 #1 (max sticks per turn)
--          bcd_sel     -- 4-bit BCD to CD4511 #2 (current selection)
--          led_p1      -- player 1 LED (both on=IDLE, active on=PLAY, blink=WIN)
--          led_p2      -- player 2 LED (both on=IDLE, active on=PLAY, blink=WIN)
--          led_j1      -- joker 1 available for the active player
--          led_j2      -- joker 2 available for the active player
--
-- Carousel : in S_IDLE the SR chain shows a fill animation.
--            carousel_r is a 6-bit up-counter driven by clk1 (natural overflow).
--            0-40: LEDs fill up; 41-63: all 40 LEDs on (hold);
--            63->0: instant dark flash, then repeat.
--            Full cycle = 64 clk1 ticks; counter resets to 0 outside S_IDLE.
--
-- ///

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.nim_pkg.ALL;

entity ELEN0040_Nim is
    port (
        clk0        : in  std_logic;
        clk1        : in  std_logic;

        -- Active-low: 10k pull-up to VCCIO, button shorts to GND
        btn_start   : in  std_logic;
        btn_joker1  : in  std_logic;
        btn_joker2  : in  std_logic;
        btn_confirm : in  std_logic;
        btn_up      : in  std_logic;
        btn_down    : in  std_logic;
        btn_reset   : in  std_logic;

        -- TLC6C598 shift register chain (40 stick LEDs)
        sr_data     : out std_logic;
        sr_clk      : out std_logic;
        sr_latch    : out std_logic;

        -- BCD outputs to CD4511 (LE pin tied GND = transparent latch)
        bcd_max_tk  : out std_logic_vector(3 downto 0);
        bcd_sel     : out std_logic_vector(3 downto 0);

        -- Player LEDs: both on=IDLE, one on per turn=PLAY, winner blinks=WIN
        led_p1      : out std_logic;
        led_p2      : out std_logic;

        -- Joker LEDs: on while the active player still has that joker
        led_j1      : out std_logic;
        led_j2      : out std_logic
    );
end ELEN0040_Nim;

architecture rtl of ELEN0040_Nim is

    -- Internal signals connecting sub-modules to each other and to I/O logic
    signal rst_sync       : std_logic;                      -- active-high reset for the FSM
    signal rnd_s          : std_logic_vector(6 downto 0);   -- random bits from nim_sr counter
    signal btn_raw        : std_logic_vector(5 downto 0);   -- active-high button states (inverted from pins)
    signal btn_press_s    : std_logic_vector(5 downto 0);   -- one-cycle pulse on button PRESS
    signal btn_release_s  : std_logic_vector(5 downto 0);   -- one-cycle pulse on button RELEASE
    signal sticks_s       : unsigned(5 downto 0);           -- sticks remaining (from FSM)
    signal max_take_s     : unsigned(3 downto 0);           -- max sticks per turn (from FSM)
    signal selection_s    : unsigned(3 downto 0);           -- current player selection (from FSM)
    signal player_s       : std_logic;                      -- active player: '0'=P1, '1'=P2
    signal winner_s       : std_logic;                      -- winning player after game ends
    signal state_s        : state_t;                        -- current FSM state
    signal joker1_avail_s : std_logic;                      -- Joker 1 available for active player
    signal joker2_avail_s : std_logic;                      -- Joker 2 available for active player

    -- Winner blink: toggles every clk1 rising edge -> clk1/2 square wave
    signal win_blink_r : std_logic := '0';

    -- Idle carousel: 6-bit up-counter (0->63, natural overflow) clocked by clk1.
    -- Values 0-40 fill LEDs one by one; 41-63 hold all 40 LEDs on; 63->0 snaps dark.
    signal carousel_r  : unsigned(5 downto 0) := (others => '0');

    -- Mux output fed to nim_sr: carousel value in S_IDLE, real stick count otherwise
    signal led_count_s : unsigned(5 downto 0);

    component nim_debounce is
        port (
            clk1    : in  std_logic;
            raw     : in  std_logic_vector(5 downto 0);
            db_edge : out std_logic_vector(5 downto 0);
            db_fall : out std_logic_vector(5 downto 0)
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
            db_fall : in  std_logic_vector(5 downto 0);
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

    -- Winner blink : toggles on every clk1 rising edge.
    process(clk1)
    begin
        if rising_edge(clk1) then
            win_blink_r <= not win_blink_r;
        end if;
    end process;

    -- Idle Caroussel :

    process(clk1)
    begin
        if rising_edge(clk1) then
            if state_s /= S_IDLE then
                carousel_r <= (others => '0');   -- freeze at 0 outside IDLE to remove bugs
            else
                carousel_r <= carousel_r + 1;    -- free-run; 63 overflows to 0 naturally
            end if;
        end if;
    end process;

    -- Feed the carousel counter to nim_sr during IDLE; use real sticks otherwise
    led_count_s <= carousel_r when state_s = S_IDLE else sticks_s;



    -- Button and reset signal conditioning :
    -- Active-low reset pin -> active-high signal for the FSM
    rst_sync <= not btn_reset;

    -- Invert all six active-low button pins to active-high for nim_debounce.
    -- Bit order must match nim_pkg constants (B_START=0 .. B_DOWN=5).
    btn_raw <= (not btn_down) & (not btn_up) & (not btn_confirm) &
               (not btn_joker2) & (not btn_joker1) & (not btn_start);



    -- Other Module instantiations

    -- Edge detector: produces one-cycle press and release pulses from raw buttons
    u_deb : nim_debounce
        port map (
            clk1    => clk1,
            raw     => btn_raw,
            db_edge => btn_press_s,
            db_fall => btn_release_s
        );

    -- Shift register driver: serialises the LED pattern and exposes random bits
    u_sr : nim_sr
        port map (
            clk0     => clk0,
            sticks   => led_count_s,    -- carousel in S_IDLE, real sticks otherwise
            sr_data  => sr_data,
            sr_clk   => sr_clk,
            sr_latch => sr_latch,
            sr_rnd   => rnd_s
        );

    -- Game FSM: handles all game logic, joker effects, and state transitions
    u_fsm : nim_fsm
        port map (
            clk1    => clk1,
            rst     => rst_sync,
            rnd     => rnd_s,
            db_edge => btn_press_s,
            db_fall => btn_release_s,
            sticks  => sticks_s,
            max_tk  => max_take_s,
            sel     => selection_s,
            player  => player_s,
            winner  => winner_s,
            state   => state_s,
            j1_av   => joker1_avail_s,
            j2_av   => joker2_avail_s
        );



    -- BCD outputs: pure wires to CD4511 decoders

    bcd_max_tk <= std_logic_vector(max_take_s);
    bcd_sel    <= std_logic_vector(selection_s);


  
    -- LED outputs :
    -- led_p1: blinks in WIN if P1 won; on in IDLE (waiting); on in PLAY when P1's turn
    led_p1 <= win_blink_r  when (state_s = S_WIN  and winner_s = '0') else
              '1'           when  state_s = S_IDLE                      else
              not player_s  when  state_s = S_PLAY                      else
              '0';

    -- led_p2: blinks in WIN if P2 won; on in IDLE (waiting); on in PLAY when P2's turn
    led_p2 <= win_blink_r  when (state_s = S_WIN  and winner_s = '1') else
              '1'           when  state_s = S_IDLE                      else
              player_s      when  state_s = S_PLAY                      else
              '0';

    -- Joker LEDs are only meaningful during S_PLAY; forced off in all other states
    led_j1 <= joker1_avail_s when state_s = S_PLAY else '0';
    led_j2 <= joker2_avail_s when state_s = S_PLAY else '0';

end rtl;
