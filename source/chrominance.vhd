--------------------------------------------------------------------------------
-- Etage 2c : decodage de la CHROMINANCE d'une ligne Robot 36 (couleur)
--
-- Ligne Robot 36 (150 ms) :
--   synchro 1200 Hz 9 ms | palier 1500 Hz 3 ms | Y : 320 px x 275 us (88 ms)
--   | SEPARATEUR 4,5 ms | PALIER 1900 Hz 1,5 ms | CHROMA : 320 px x 137,5 us (44 ms)
--
--   Le separateur dit QUELLE chroma suit :
--     1500 Hz (T ~ 667 us) -> ligne paire  -> R-Y (Cr)
--     2300 Hz (T ~ 435 us) -> ligne impaire-> B-Y (Cb)
--   Une ligne ne transporte donc qu'UNE des deux chromas : l'autre est reprise
--   de la ligne precedente (memorisee dans un buffer de ligne).
--
-- Ce bloc demarre quand "luminance" signale la fin du balayage Y (lum_end).
-- Il n'utilise PAS sync_1200 : la ligne est deja calee par luminance.
--
-- Memoires internes (320 x 8 bits chacune) :
--   buf_Y  : ecrit par luminance pendant SCAN_Y (lum_we, lum_x, lum_data)
--   buf_Cr : derniere ligne Cr recue
--   buf_Cb : derniere ligne Cb recue
--
-- A la fin de chaque pixel chroma x : sortie (Y, Cr, Cb, x) + impulsion pix_val.
-- Apres le dernier pixel (ou si une synchro coupe la ligne) : line_end.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity chrominance is
    generic (
        CLK_MHZ   : integer := 100;    -- frequence d'horloge en MHz
        RETARD_US : integer := 0       -- decalage fin de la chroma (reglage couleur / gris)
    );
    port (
        clk      : in  std_logic;
        raz      : in  std_logic;                        -- reset synchrone, actif a '1'
        sync_val : in  std_logic;                        -- nouvelle synchro : on abandonne la ligne
        T        : in  std_logic_vector(11 downto 0);    -- periode en us (perio_metre)

        -- cote luminance
        lum_we   : in  std_logic;                        -- pixel Y pret
        lum_x    : in  std_logic_vector(8 downto 0);
        lum_data : in  std_logic_vector(7 downto 0);
        lum_end  : in  std_logic;                        -- fin du balayage Y

        -- pixel couleur complet
        Y        : out std_logic_vector(7 downto 0);
        Cr       : out std_logic_vector(7 downto 0);
        Cb       : out std_logic_vector(7 downto 0);
        x_out    : out std_logic_vector(8 downto 0);
        pix_val  : out std_logic;                        -- '1' 1 cycle : Y,Cr,Cb,x valides
        line_end : out std_logic;                        -- '1' 1 cycle : fin de la ligne couleur
        paire    : out std_logic                         -- debug : '1' si ligne Cr
    );
end entity chrominance;

architecture rtl of chrominance is

    constant SEP_CYC   : integer := 4500 * CLK_MHZ;                  -- 450 000
    constant PAL_CYC   : integer := (1500 + RETARD_US) * CLK_MHZ;    -- 150 000
    constant PIX_CYC   : integer := 1375 * CLK_MHZ / 10;             -- 13 750 (137,5 us)
    constant NB_PIX    : integer := 320;

    -- fenetre de vote au milieu du separateur (1 ms .. 3,5 ms)
    constant VOTE_DEB  : integer := 1000 * CLK_MHZ;
    constant VOTE_FIN  : integer := 3500 * CLK_MHZ;
    constant SEUIL_T   : integer := 550;    -- us : > 550 -> 1500 Hz, < 550 -> 2300 Hz

    type etat_t is (ATTENTE, SEP, PALIER, SCAN_C);
    signal etat   : etat_t := ATTENTE;
    signal timer  : integer range 0 to SEP_CYC := 0;
    signal x      : integer range 0 to 319 := 0;
    signal vote   : integer range -VOTE_FIN to VOTE_FIN := 0;   -- >0 : Cr, <0 : Cb
    signal est_cr : std_logic := '1';

    -- ROM periode -> niveau (meme loi que la luminance : 1500 Hz=0, 2300 Hz=255)
    signal niveau : std_logic_vector(7 downto 0);

    -- buffers de ligne (init 128 = chroma neutre -> gris tant qu'on n'a rien recu)
    type ligne_t is array (0 to 319) of std_logic_vector(7 downto 0);
    signal buf_Y  : ligne_t := (others => x"80");
    signal buf_Cr : ligne_t := (others => x"80");
    signal buf_Cb : ligne_t := (others => x"80");
    signal rd_Y, rd_Cr, rd_Cb : std_logic_vector(7 downto 0) := x"80";

begin

    u_rom : entity work.rom_periode_gris
        port map ( clk => clk, addr => T, data_out => niveau );

    paire <= est_cr;

    ----------------------------------------------------------------------------
    -- Buffer Y : ecrit par luminance, lu a l'adresse x du balayage chroma
    ----------------------------------------------------------------------------
    p_buf_y : process(clk)
    begin
        if rising_edge(clk) then
            if lum_we = '1' and unsigned(lum_x) < NB_PIX then
                buf_Y(to_integer(unsigned(lum_x))) <= lum_data;
            end if;
            rd_Y <= buf_Y(x);
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Buffers Cr / Cb : lecture permanente a l'adresse x (x reste stable
    -- 13 750 cycles, la valeur lue est donc prete bien avant la fin du pixel)
    ----------------------------------------------------------------------------
    p_buf_c : process(clk)
    begin
        if rising_edge(clk) then
            if etat = SCAN_C and timer >= PIX_CYC - 1 then
                if est_cr = '1' then
                    buf_Cr(x) <= niveau;
                else
                    buf_Cb(x) <= niveau;
                end if;
            end if;
            rd_Cr <= buf_Cr(x);
            rd_Cb <= buf_Cb(x);
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Machine a etats de la seconde moitie de ligne
    ----------------------------------------------------------------------------
    p_fsm : process(clk)
    begin
        if rising_edge(clk) then
            pix_val  <= '0';
            line_end <= '0';

            if raz = '1' then
                etat  <= ATTENTE;
                timer <= 0;
                x     <= 0;
                vote  <= 0;

            elsif sync_val = '1' then
                -- nouvelle ligne : si on etait en cours, on clot quand meme la
                -- ligne pour que le numero de ligne continue d'avancer
                if etat /= ATTENTE then
                    line_end <= '1';
                end if;
                etat  <= ATTENTE;
                timer <= 0;
                x     <= 0;

            elsif lum_end = '1' then           -- fin de Y : debut du separateur
                etat  <= SEP;
                timer <= 0;
                vote  <= 0;
                x     <= 0;

            else
                case etat is
                    when ATTENTE =>
                        null;

                    -- separateur 4,5 ms : vote sur la frequence (1500 ou 2300 Hz)
                    when SEP =>
                        if timer >= VOTE_DEB and timer < VOTE_FIN then
                            if unsigned(T) > SEUIL_T then
                                vote <= vote + 1;
                            else
                                vote <= vote - 1;
                            end if;
                        end if;
                        if timer = SEP_CYC - 1 then
                            if vote > 0 then est_cr <= '1'; else est_cr <= '0'; end if;
                            etat  <= PALIER;
                            timer <= 0;
                        else
                            timer <= timer + 1;
                        end if;

                    -- palier neutre 1900 Hz, 1,5 ms
                    when PALIER =>
                        if timer = PAL_CYC - 1 then
                            etat  <= SCAN_C;
                            timer <= 0;
                            x     <= 0;
                        else
                            timer <= timer + 1;
                        end if;

                    -- 320 pixels chroma de 137,5 us
                    when SCAN_C =>
                        if timer >= PIX_CYC - 1 then
                            timer <= 0;
                            Y     <= rd_Y;
                            if est_cr = '1' then
                                Cr <= niveau;   -- chroma de cette ligne
                                Cb <= rd_Cb;    -- chroma de la ligne precedente
                            else
                                Cr <= rd_Cr;
                                Cb <= niveau;
                            end if;
                            x_out   <= std_logic_vector(to_unsigned(x, 9));
                            pix_val <= '1';
                            if x >= NB_PIX - 1 then
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
