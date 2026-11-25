--------------------------------------------------------------------------------
-- Etage 2b : decodage de la luminance d'une ligne (niveaux de gris)
--
-- Deux modes, choisis par l'entree mode_r8 :
--
--  Robot 8 (noir et blanc, mode_r8 = '1') : image 160 x 120, ~15 lignes/s
--    synchro 1200 Hz 10 ms | Y : 160 pixels x 350 us (56 ms)
--
--  Robot 36 (mode_r8 = '0') : image 320 x 240, ligne de 150 ms
--    synchro 1200 Hz 9 ms | palier 1500 Hz 3 ms | Y : 320 pixels x 275 us (88 ms)
--    | separateur 4,5 ms | palier 1,5 ms | chroma 44 ms (IGNOREE en mode gris)
--
-- Machine a etats calee sur la ligne :
--   ATTENTE : attend sync_val (fin de synchro)
--   PALIER  : attend la fin du palier (Robot 36 seulement)
--   SCAN_Y  : NB_PIX pixels ; a la fin de chaque pixel on sort le gris,
--             l'abscisse x et une impulsion pix_val. Apres le dernier pixel :
--             impulsion line_end puis retour en ATTENTE.
-- Une nouvelle synchro, quel que soit l'etat, recale la ligne.
--
-- Retard de detec_sync : sync_val arrive TROU_US apres la vraie fin de synchro.
--   Robot 36 : on raccourcit le palier de TROU_US.
--   Robot 8  : pas de palier, on est deja TROU_US dans la ligne -> on demarre
--              SCAN_Y avec le compteur de temps (et x) deja avances.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity luminance is
    generic (
        CLK_MHZ : integer := 100;      -- frequence d'horloge en MHz
        TROU_US : integer := 500       -- retard de sync_val (voir detec_sync)
    );
    port (
        clk      : in  std_logic;
        raz      : in  std_logic;                        -- reset synchrone, actif a '1'
        mode_r8  : in  std_logic;                        -- '1' : Robot 8, '0' : Robot 36
        sync_val : in  std_logic;                        -- fin de synchro (detec_sync)
        T        : in  std_logic_vector(11 downto 0);    -- periode en us (perio_metre)

        data_out : out std_logic_vector(7 downto 0);     -- niveau de gris du pixel
        x_out    : out std_logic_vector(8 downto 0);     -- abscisse du pixel
        pix_val  : out std_logic;                        -- '1' 1 cycle : pixel pret a ecrire
        line_end : out std_logic                         -- '1' 1 cycle : fin de la ligne
    );
end entity luminance;

architecture rtl of luminance is

    -- Robot 36
    constant R36_PIX_CYC : integer := 275 * CLK_MHZ;                 -- 27 500
    constant R36_NB_PIX  : integer := 320;
    constant R36_PALIER  : integer := (3000 - TROU_US) * CLK_MHZ;    -- > 0

    -- Robot 8 : on est deja TROU_US dans la ligne quand sync_val arrive
    constant R8_PIX_CYC  : integer := 350 * CLK_MHZ;                 -- 35 000
    constant R8_NB_PIX   : integer := 160;
    constant R8_AVANCE   : integer := TROU_US * CLK_MHZ;             -- 50 000 cycles
    constant R8_X0       : integer := R8_AVANCE / R8_PIX_CYC;        -- pixels deja passes (1)
    constant R8_TIMER0   : integer := R8_AVANCE mod R8_PIX_CYC;      -- temps deja passe dans le pixel

    type etat_t is (ATTENTE, PALIER, SCAN_Y);
    signal etat    : etat_t := ATTENTE;
    signal timer   : integer range 0 to R36_PALIER := 0;
    signal x       : integer range 0 to 319 := 0;
    signal gris    : std_logic_vector(7 downto 0);

    signal pix_cyc : integer range 0 to R8_PIX_CYC;
    signal nb_pix  : integer range 0 to 320;

begin

    u_rom : entity work.rom_periode_gris
        port map ( clk => clk, addr => T, data_out => gris );

    pix_cyc <= R8_PIX_CYC when mode_r8 = '1' else R36_PIX_CYC;
    nb_pix  <= R8_NB_PIX  when mode_r8 = '1' else R36_NB_PIX;

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
                if mode_r8 = '1' then
                    etat  <= SCAN_Y;
                    x     <= R8_X0;
                    timer <= R8_TIMER0;
                    -- le pixel 0 est deja termine : on l'ecrit tout de suite avec
                    -- le gris actuel (la mesure de periode a elle aussi du retard)
                    if R8_X0 >= 1 then
                        data_out <= gris;
                        x_out    <= (others => '0');
                        pix_val  <= '1';
                    end if;
                else
                    etat  <= PALIER;
                    timer <= 0;
                end if;

            else
                case etat is
                    when ATTENTE =>
                        null;

                    when PALIER =>
                        if timer = R36_PALIER - 1 then
                            etat  <= SCAN_Y;
                            timer <= 0;
                            x     <= 0;
                        else
                            timer <= timer + 1;
                        end if;

                    when SCAN_Y =>
                        if timer >= pix_cyc - 1 then
                            timer    <= 0;
                            data_out <= gris;     -- gris mesure en fin de pixel
                            x_out    <= std_logic_vector(to_unsigned(x, 9));
                            pix_val  <= '1';
                            if x >= nb_pix - 1 then
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
