--------------------------------------------------------------------------------
-- ROM periode (us) -> niveau de gris (0..255)   -- SEULE ROM du projet
--
-- En SSTV la luminance est LINEAIRE EN FREQUENCE :
--      1500 Hz -> 0 (noir)      2300 Hz -> 255 (blanc)
--      gris = 255 * (f - 1500) / 800     avec f = 1e6 / T
--   => gris = 255 * (1e6 - 1500*T) / (800*T)
--
-- L'ancienne table etait lineaire en PERIODE : a 1900 Hz (gris moyen) elle
-- donnait 154 au lieu de 128 (gris moyens trop clairs).
--
-- La table est calculee a l'elaboration par une fonction (pas de recopie de
-- valeurs a la main) pour les 4096 periodes possibles sur 12 bits :
--   T < 434 us (> 2300 Hz) -> 255,   T > 666 us (< 1500 Hz) -> 0
-- Vivado la synthetise en ROM (LUT ou BRAM). Sortie registree : 1 cycle de latence.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rom_periode_gris is
    port (
        clk      : in  std_logic;
        addr     : in  std_logic_vector(11 downto 0);   -- periode en us (0 a 4095)
        data_out : out std_logic_vector(7 downto 0)     -- niveau de gris (0 a 255)
    );
end entity rom_periode_gris;

architecture rtl of rom_periode_gris is

    type rom_type is array (0 to 4095) of std_logic_vector(7 downto 0);

    function gris_de_periode(p : integer) return integer is
        variable g : integer;
    begin
        if p < 434 then                  -- frequence >= 2300 Hz (et p = 0)
            return 255;
        elsif p > 666 then               -- frequence <= 1500 Hz
            return 0;
        end if;
        g := (255 * (1000000 - 1500 * p) + 400 * p) / (800 * p);   -- +400p : arrondi
        if g < 0 then g := 0; elsif g > 255 then g := 255; end if;
        return g;
    end function;

    function init_rom return rom_type is
        variable r : rom_type;
    begin
        for p in 0 to 4095 loop
            r(p) := std_logic_vector(to_unsigned(gris_de_periode(p), 8));
        end loop;
        return r;
    end function;

    constant ROM_DATA : rom_type := init_rom;

begin

    process(clk)
    begin
        if rising_edge(clk) then
            data_out <= ROM_DATA(to_integer(unsigned(addr)));
        end if;
    end process;

end architecture rtl;
