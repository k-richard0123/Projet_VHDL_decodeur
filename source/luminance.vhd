--------------------------------------------------------------------------------
-- Etage 2b : decodage de la luminance d'une ligne Robot 36 (niveaux de gris)
--
-- Ligne Robot 36 (150 ms) :
--   synchro 1200 Hz 9 ms | palier 1500 Hz 3 ms | Y : 320 pixels x 275 us (88 ms)
--   | separateur 4,5 ms | palier 1,5 ms | chroma 44 ms (IGNOREE en mode gris)
--
-- Machine a etats calee sur la ligne (avant : compteur libre sans lien avec la
-- synchro, et seuil 275 000 000 jamais atteint par un compteur 24 bits) :
--   ATTENTE : attend sync_val (fin de synchro)
--   PALIER  : attend PALIER_US
--   SCAN_Y  : 320 pixels ; a la fin de chaque pixel (275 us) on sort le gris,
--             l'abscisse x et une impulsion pix_val. Apres le pixel 319 :
--             impulsion line_end puis retour en ATTENTE (la chroma est ignoree).
-- Une nouvelle synchro, quel que soit l'etat, recale la ligne.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity luminance is
    generic (
        CLK_MHZ   : integer := 100;    -- frequence d'horloge en MHz
        PALIER_US : integer := 3000;   -- duree du palier apres sync_val
        PIXEL_NS  : integer := 275000  -- duree d'un pixel Y en ns (275 us)
    );
    port (
        clk      : in  std_logic;
        raz      : in  std_logic;                        -- reset synchrone, actif a '1'
        sync_val : in  std_logic;                        -- fin de synchro (detec_sync)
        T        : in  std_logic_vector(11 downto 0);    -- periode en us (perio_metre)

        data_out : out std_logic_vector(7 downto 0);     -- niveau de gris du pixel
        x_out    : out std_logic_vector(8 downto 0);     -- abscisse du pixel (0..319)
        pix_val  : out std_logic;                        -- '1' 1 cycle : pixel pret a ecrire
        line_end : out std_logic                         -- '1' 1 cycle : fin des 320 pixels
    );
end entity luminance;

architecture rtl of luminance is

    constant PALIER_CYC : integer := PALIER_US * CLK_MHZ;          -- 300 000
    constant PIXEL_CYC  : integer := (PIXEL_NS * CLK_MHZ) / 1000;  -- 27 500

    type etat_t is (ATTENTE, PALIER, SCAN_Y);
    signal etat  : etat_t := ATTENTE;
    signal timer : integer range 0 to PALIER_CYC := 0;
    signal x     : integer range 0 to 319 := 0;
    signal gris  : std_logic_vector(7 downto 0);

begin

    u_rom : entity work.rom_periode_gris
        port map ( clk => clk, addr => T, data_out => gris );

    process(clk)
    begin
        if rising_edge(clk) then
            pix_val  <= '0';
            line_end <= '0';

            if raz = '1' then
                etat     <= ATTENTE;
                timer    <= 0;
                x        <= 0;
                data_out <= (others => '0');
                x_out    <= (others => '0');

            elsif sync_val = '1' then          -- (re)calage sur chaque synchro
                etat  <= PALIER;
                timer <= 0;

            else
                case etat is
                    when ATTENTE =>
                        null;

                    when PALIER =>
                        if timer = PALIER_CYC - 1 then
                            etat  <= SCAN_Y;
                            timer <= 0;
                            x     <= 0;
                        else
                            timer <= timer + 1;
                        end if;

                    when SCAN_Y =>
                        if timer = PIXEL_CYC - 1 then
                            timer    <= 0;
                            data_out <= gris;     -- gris mesure en fin de pixel
                            x_out    <= std_logic_vector(to_unsigned(x, 9));
                            pix_val  <= '1';
                            if x = 319 then
                                line_end <= '1';
                                etat     <= ATTENTE;
                            else
                                x <= x + 1;
                            end if;
                        else
                            timer <= timer + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;
