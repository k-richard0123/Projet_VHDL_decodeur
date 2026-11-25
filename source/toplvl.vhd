--------------------------------------------------------------------------------
-- TOP : decodeur SSTV Robot 36 -> image 320x240 en NIVEAUX DE GRIS sur VGA
--
--   micro PDM -> PDC_sig16 -> perio_metre -> detec_sync -+-> luminance -> VRAM -> VGA
--                                        \______________/
--
--  * UN SEUL domaine d'horloge (100 MHz). Les "lentes" cadences (1 us, micro,
--    pixel VGA) sont des clock enables, jamais des horloges fabriquees en logique.
--  * UN SEUL reset interne "rst" (actif a '1', synchronise), venant du bouton
--    CPU_RESET de la carte qui, lui, est ACTIF A '0'.
--  * Ecran BLANC au demarrage (VRAM initialisee a 255). btn_clear le remet en
--    blanc et ramene l'ecriture en haut de l'image.
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_sstv is
    Port (
        clk_100mhz : in  std_logic;
        cpu_resetn : in  std_logic;     -- bouton CPU_RESET : '0' quand appuye
        btn_clear  : in  std_logic;     -- bouton BTNC      : '1' quand appuye

        data_pdm   : in  std_logic;
        clk_mic    : out std_logic;
        lr_sel     : out std_logic;

        vga_hsync  : out std_logic;
        vga_vsync  : out std_logic;
        vga_R      : out std_logic_vector(3 downto 0);
        vga_G      : out std_logic_vector(3 downto 0);
        vga_B      : out std_logic_vector(3 downto 0)
    );
end top_sstv;

architecture Structural of top_sstv is

    -- tolerance de detec_sync, reportee sur le palier de luminance
    constant TROU_US : integer := 500;

    -- reset et bouton clear synchronises
    signal rst_s1, rst      : std_logic := '1';
    signal clr_s1, clr_s2   : std_logic := '0';
    signal clr_d            : std_logic := '0';
    signal clear_pulse      : std_logic;

    -- clock enable 1 us
    signal div_1us   : integer range 0 to 99 := 0;
    signal tick_1us  : std_logic := '0';

    signal pcm_audio  : std_logic_vector(15 downto 0);
    signal periode_us : std_logic_vector(11 downto 0);
    signal sync_valid : std_logic;

    signal pixel_gris : std_logic_vector(7 downto 0);
    signal pixel_x    : std_logic_vector(8 downto 0);
    signal pixel_we   : std_logic;
    signal line_end   : std_logic;

    signal y_coord    : unsigned(7 downto 0) := (others => '0');  -- 0 a 239
    signal vram_waddr : std_logic_vector(16 downto 0);

begin

    ----------------------------------------------------------------------------
    -- Reset (bouton actif a '0' -> reset interne actif a '1') et bouton clear
    ----------------------------------------------------------------------------
    p_boutons : process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            rst_s1 <= not cpu_resetn;
            rst    <= rst_s1;
            clr_s1 <= btn_clear;
            clr_s2 <= clr_s1;
            clr_d  <= clr_s2;
        end if;
    end process;

    clear_pulse <= clr_s2 and not clr_d;      -- 1 seul cycle par appui

    ----------------------------------------------------------------------------
    -- tick_1us : '1' un cycle sur 100
    ----------------------------------------------------------------------------
    p_tick : process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if rst = '1' or div_1us = 99 then
                div_1us <= 0;
            else
                div_1us <= div_1us + 1;
            end if;
            if div_1us = 99 then tick_1us <= '1'; else tick_1us <= '0'; end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Chaine de decodage
    ----------------------------------------------------------------------------
    inst_mic : entity work.PDC_sig16
        port map (
            clk_100mhz => clk_100mhz,
            reset      => rst,
            data_pdm   => data_pdm,
            clk_mic    => clk_mic,
            lr_sel     => lr_sel,
            pcm_data   => pcm_audio,
            sample_val => open
        );

    inst_freq : entity work.perio_metre
        generic map ( HYST => 512 )
        port map (
            clk      => clk_100mhz,
            raz      => rst,
            tick_1us => tick_1us,
            sig_in   => pcm_audio,
            T        => periode_us,
            T_val    => open
        );

    inst_sync : entity work.detec_sync
        generic map ( SYNC_MIN_US => 6000, TROU_US => TROU_US )
        port map (
            clk      => clk_100mhz,
            raz      => rst,
            tick_1us => tick_1us,
            T        => periode_us,
            sync     => open,
            sync_val => sync_valid      -- 1 cycle, a la fin de la synchro (+TROU_US)
        );

    inst_lum : entity work.luminance
        generic map ( CLK_MHZ => 100, PALIER_US => 3000 - TROU_US )
        port map (
            clk      => clk_100mhz,
            raz      => rst,
            sync_val => sync_valid,
            T        => periode_us,     -- les 12 bits (avant : 10 bits -> repliement)
            data_out => pixel_gris,
            x_out    => pixel_x,
            pix_val  => pixel_we,
            line_end => line_end
        );

    ----------------------------------------------------------------------------
    -- Numero de ligne : avance a chaque fin de ligne, revient en haut apres 240
    ----------------------------------------------------------------------------
    p_ligne : process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if rst = '1' or clear_pulse = '1' then
                y_coord <= (others => '0');
            elsif line_end = '1' then
                if y_coord = 239 then
                    y_coord <= (others => '0');
                else
                    y_coord <= y_coord + 1;
                end if;
            end if;
        end if;
    end process;

    -- Adresse = y*320 + x = (y<<8) + (y<<6) + x
    -- (line_end arrive dans le meme cycle que le dernier pix_val : y n'a pas
    --  encore change, le pixel 319 est donc bien ecrit sur la bonne ligne)
    vram_waddr <= std_logic_vector(shift_left(resize(y_coord, 17), 8) +
                                   shift_left(resize(y_coord, 17), 6) +
                                   resize(unsigned(pixel_x), 17));

    ----------------------------------------------------------------------------
    -- VRAM + VGA
    ----------------------------------------------------------------------------
    inst_vga : entity work.vga_display
        port map (
            clk          => clk_100mhz,
            rst          => rst,
            wr_addr      => vram_waddr,
            vram_data_in => pixel_gris,
            wr_en        => pixel_we,
            clear        => clear_pulse,   -- efface en blanc
            HSYNC        => vga_hsync,
            VSYNC        => vga_vsync,
            VGA_R        => vga_R,
            VGA_G        => vga_G,
            VGA_B        => vga_B
        );

end Structural;
