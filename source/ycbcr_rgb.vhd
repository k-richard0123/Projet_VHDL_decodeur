--------------------------------------------------------------------------------
-- Conversion Y Cr Cb (8 bits, 128 = chroma neutre) -> RGB 4:4:4 (12 bits)
--
--   R = Y + 1,402 (Cr-128)
--   G = Y - 0,344 (Cb-128) - 0,714 (Cr-128)
--   B = Y + 1,772 (Cb-128)
--
-- Coefficients en virgule fixe x256 : 359, 88, 183, 454.
-- Resultat sature a 0..255, puis on garde les 4 bits de poids fort (VGA 4 bits).
--
-- Pipeline 2 etages (multiplications, puis sommes + saturation) :
-- les signaux val / x / last sont retardes d'autant pour rester alignes.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ycbcr_rgb is
    port (
        clk      : in  std_logic;
        Y        : in  std_logic_vector(7 downto 0);
        Cr       : in  std_logic_vector(7 downto 0);
        Cb       : in  std_logic_vector(7 downto 0);
        x_in     : in  std_logic_vector(8 downto 0);
        val_in   : in  std_logic;
        last_in  : in  std_logic;

        rgb      : out std_logic_vector(11 downto 0);    -- R(11..8) G(7..4) B(3..0)
        x_out    : out std_logic_vector(8 downto 0);
        val_out  : out std_logic;
        last_out : out std_logic
    );
end entity ycbcr_rgb;

architecture rtl of ycbcr_rgb is

    -- etage 1
    signal y1                   : integer range 0 to 255 := 0;
    signal r_cr, g_cb, g_cr, b_cb : integer range -65536 to 65535 := 0;
    signal x1                   : std_logic_vector(8 downto 0) := (others => '0');
    signal val1, last1          : std_logic := '0';

    function sature(v : integer) return std_logic_vector is
        variable u : unsigned(7 downto 0);
    begin
        if v < 0 then
            return "0000";
        elsif v > 255 then
            return "1111";
        else
            u := to_unsigned(v, 8);
            return std_logic_vector(u(7 downto 4));
        end if;
    end function;

begin

    process(clk)
        variable dcr, dcb : integer range -128 to 127;
        variable r, g, b  : integer;
    begin
        if rising_edge(clk) then
            -- etage 1 : produits (Cr-128, Cb-128 sont signes)
            dcr  := to_integer(unsigned(Cr)) - 128;
            dcb  := to_integer(unsigned(Cb)) - 128;
            y1   <= to_integer(unsigned(Y));
            r_cr <= 359 * dcr;
            g_cb <=  88 * dcb;
            g_cr <= 183 * dcr;
            b_cb <= 454 * dcb;
            x1    <= x_in;
            val1  <= val_in;
            last1 <= last_in;

            -- etage 2 : sommes (/256 avec arrondi) + saturation
            r := y1 + (r_cr + 128) / 256;
            g := y1 - (g_cb + g_cr - 128) / 256;
            b := y1 + (b_cb + 128) / 256;
            rgb      <= sature(r) & sature(g) & sature(b);
            x_out    <= x1;
            val_out  <= val1;
            last_out <= last1;
        end if;
    end process;

end architecture rtl;
