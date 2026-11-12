--------------------------------------------------------------------------------
-- Etage 4 : controleur VGA 640x480 @ 60 Hz (Nexys 4)
--
--  * Horloge pixel 25 MHz obtenue par clock enable (pix_en 1 cycle sur 4)
--    sur l'horloge 100 MHz : tout le design reste dans un seul domaine d'horloge
--  * Image 320x240 doublee en 640x480 : x = h_cnt/2, y = v_cnt/2
--      rd_addr = y*320 + x = (y<<8) + (y<<6) + x
--  * Niveau de gris 8 bits -> 4 bits de poids fort sur R, G et B
--  * HSYNC et VSYNC actifs a '0' (polarite standard du 640x480@60)
--
--  Chronogramme (en cycles clk 100 MHz) :
--    E0 : compteurs mis a jour (pixel N)
--    E1 : rd_addr registre (adresse du pixel N)
--    E2 : pixel_out disponible (latence 1 de la VRAM)
--    E4 : pix_en -> couleurs, HSYNC, VSYNC registres pour le pixel N
--  Couleurs et synchros sont registrees ensemble : elles restent alignees.
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vga_controller is
    Port ( clk       : in  std_logic;                          -- 100 MHz
           rst       : in  std_logic;                          -- reset synchrone, actif a '1'

           -- Vers / depuis la VRAM (port B)
           rd_addr   : out std_logic_vector(16 downto 0);
           pixel_out : in  std_logic_vector(7 downto 0);

           -- Vers le connecteur VGA
           HSYNC     : out std_logic;
           VSYNC     : out std_logic;
           VGA_R     : out std_logic_vector(3 downto 0);
           VGA_G     : out std_logic_vector(3 downto 0);
           VGA_B     : out std_logic_vector(3 downto 0)
         );
end vga_controller;

architecture Behavioral of vga_controller is

    -- Horizontal (en pixels)
    constant H_VISIBLE : integer := 640;
    constant H_FP      : integer := 16;
    constant H_SYNC    : integer := 96;
    constant H_BP      : integer := 48;
    constant H_TOTAL   : integer := H_VISIBLE + H_FP + H_SYNC + H_BP;   -- 800

    -- Vertical (en lignes)
    constant V_VISIBLE : integer := 480;
    constant V_FP      : integer := 10;
    constant V_SYNC    : integer := 2;
    constant V_BP      : integer := 29;
    constant V_TOTAL   : integer := V_VISIBLE + V_FP + V_SYNC + V_BP;   -- 521

    signal div_cnt  : unsigned(1 downto 0) := (others => '0');
    signal pix_en   : std_logic;

    signal h_cnt    : unsigned(9 downto 0) := (others => '0');          -- 0 .. 799
    signal v_cnt    : unsigned(9 downto 0) := (others => '0');          -- 0 .. 520
    signal video_on : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Clock enable 25 MHz : pix_en = '1' un cycle sur quatre
    ----------------------------------------------------------------------------
    p_div : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                div_cnt <= (others => '0');
            else
                div_cnt <= div_cnt + 1;                         -- 2 bits : boucle 0..3
            end if;
        end if;
    end process;

    pix_en <= '1' when div_cnt = "11" else '0';

    -- Zone visible
    video_on <= '1' when (h_cnt < H_VISIBLE and v_cnt < V_VISIBLE) else '0';

    ----------------------------------------------------------------------------
    -- Compteurs h/v et sorties (couleurs + synchros), mis a jour a pix_en
    ----------------------------------------------------------------------------
    p_vga : process(clk)
        variable gris : std_logic_vector(3 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                h_cnt <= (others => '0');
                v_cnt <= (others => '0');
                HSYNC <= '1';
                VSYNC <= '1';
                VGA_R <= (others => '0');
                VGA_G <= (others => '0');
                VGA_B <= (others => '0');

            elsif pix_en = '1' then

                -- Couleurs : 4 bits de poids fort, noir hors zone visible (blanking)
                if video_on = '1' then
                    gris := pixel_out(7 downto 4);
                else
                    gris := (others => '0');
                end if;
                VGA_R <= gris;
                VGA_G <= gris;
                VGA_B <= gris;

                -- Synchros (actives a '0'), pour le pixel courant (h_cnt, v_cnt)
                if (h_cnt >= H_VISIBLE + H_FP) and (h_cnt < H_VISIBLE + H_FP + H_SYNC) then
                    HSYNC <= '0';
                else
                    HSYNC <= '1';
                end if;

                if (v_cnt >= V_VISIBLE + V_FP) and (v_cnt < V_VISIBLE + V_FP + V_SYNC) then
                    VSYNC <= '0';
                else
                    VSYNC <= '1';
                end if;

                -- Compteurs
                if h_cnt = H_TOTAL - 1 then
                    h_cnt <= (others => '0');
                    if v_cnt = V_TOTAL - 1 then
                        v_cnt <= (others => '0');
                    else
                        v_cnt <= v_cnt + 1;
                    end if;
                else
                    h_cnt <= h_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Adresse de lecture VRAM : pixels doubles, adresse = y*320 + x
    -- registree a chaque cycle clk (1 cycle de latence, largement < 4 cycles)
    ----------------------------------------------------------------------------
    p_addr : process(clk)
        variable x : unsigned(16 downto 0);
        variable y : unsigned(16 downto 0);
    begin
        if rising_edge(clk) then
            if video_on = '1' then
                x := resize(h_cnt(9 downto 1), 17);              -- h_cnt / 2 : 0..319
                y := resize(v_cnt(9 downto 1), 17);              -- v_cnt / 2 : 0..239
                rd_addr <= std_logic_vector(shift_left(y, 8) + shift_left(y, 6) + x);
            else
                rd_addr <= (others => '0');
            end if;
        end if;
    end process;

end Behavioral;