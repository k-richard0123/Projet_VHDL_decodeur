--------------------------------------------------------------------------------
-- TOP : decodeur SSTV -> image sur VGA
--   SW14 en bas  : Robot 8  (160 x 120, chaque pixel affiche en 2 x 2, toujours N&B)
--   SW14 en haut : Robot 36 (320 x 240)
--   SW13         : '0' niveaux de gris, '1' COULEUR (Robot 36 seulement)
--
--   micro PDM -> PDC_sig16 -> perio_metre -> detec_sync -+-> luminance --------(gris)--+
--                                        \______________/        |                      +-> VRAM 12 b -> VGA
--                                                          chrominance -> ycbcr_rgb -(couleur)
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
        vga_B      : out std_logic_vector(3 downto 0);

        -- Debug (voir debug_carte.vhd)
        sw_hyst    : in  std_logic_vector(1 downto 0);  -- SW1..0 : seuil d'hysteresis 00:128 01:64 10:256 11:512
        sw_front   : in  std_logic;                     -- SW2  : front de lecture du micro (0 = normal)
        sw_libre   : in  std_logic;                     -- SW15 : mode libre (ignore la synchro, une ligne a la cadence du mode)
        sw_mode    : in  std_logic;                     -- SW14 : '0' Robot 8, '1' Robot 36
        sw_couleur : in  std_logic;                     -- SW13 : '1' couleur (Robot 36)
        led        : out std_logic_vector(15 downto 0);
        seg        : out std_logic_vector(6 downto 0);
        an         : out std_logic_vector(7 downto 0)
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
    signal sync_image : std_logic;                       -- en-tete VIS : debut d'une nouvelle image
    signal mode_r8    : std_logic;
    signal couleur    : std_logic;                       -- '1' : chaine couleur active (Robot 36 + SW13)

    signal pixel_gris : std_logic_vector(7 downto 0);
    signal pixel_x    : std_logic_vector(8 downto 0);
    signal pixel_we   : std_logic;
    signal line_end   : std_logic;

    signal y_coord    : unsigned(7 downto 0) := (others => '0');  -- ligne : 0..239 (R36) ou 0..119 (R8)
    signal vram_waddr : std_logic_vector(16 downto 0);
    signal vram_we    : std_logic := '0';
    signal vram_data  : std_logic_vector(11 downto 0) := (others => '0');

    -- chaine couleur
    signal c_Y, c_Cr, c_Cb : std_logic_vector(7 downto 0);
    signal c_x        : std_logic_vector(8 downto 0);
    signal c_val      : std_logic;
    signal c_end      : std_logic;
    signal rgb_data   : std_logic_vector(11 downto 0);
    signal rgb_x      : std_logic_vector(8 downto 0);
    signal rgb_we     : std_logic;
    signal rgb_end    : std_logic;

    -- pixel a ecrire (gris ou couleur selon le mode)
    signal ecr_we     : std_logic;
    signal ecr_x      : std_logic_vector(8 downto 0);
    signal ecr_data   : std_logic_vector(11 downto 0);
    signal ecr_end    : std_logic;

    -- ecriture 2 x 2 du Robot 8
    signal base_addr  : unsigned(16 downto 0) := (others => '0');
    signal ecr_cnt    : integer range 0 to 3 := 0;
    signal ecr_actif  : std_logic := '0';

    -- debug
    signal sw_s1, sw_s2  : std_logic_vector(5 downto 0) := (others => '0');  -- interrupteurs synchronises
    signal hyst          : std_logic_vector(14 downto 0);
    signal sync_1200     : std_logic;
    signal sync_ligne    : std_logic;                       -- synchro donnee a luminance
    signal cpt_libre     : integer range 0 to 14999999 := 0;
    signal sync_libre    : std_logic := '0';

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
    -- Interrupteurs de debug (synchronises)
    ----------------------------------------------------------------------------
    p_sw : process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            sw_s1 <= sw_couleur & sw_mode & sw_libre & sw_front & sw_hyst;
            sw_s2 <= sw_s1;
        end if;
    end process;

    with sw_s2(1 downto 0) select hyst <=
        std_logic_vector(to_unsigned(128, 15)) when "00",     -- defaut
        std_logic_vector(to_unsigned(64, 15))  when "01",     -- son tres faible
        std_logic_vector(to_unsigned(256, 15)) when "10",
        std_logic_vector(to_unsigned(512, 15)) when others;   -- son fort et bruite

    mode_r8 <= not sw_s2(4);
    couleur <= sw_s2(5) and sw_s2(4);      -- couleur seulement en Robot 36

    -- Mode libre : une fausse synchro par duree de ligne (66,7 ms en Robot 8, 150 ms en Robot 36).
    -- Permet de voir si le son est transforme en gris meme sans synchro detectee.
    p_libre : process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            sync_libre <= '0';
            if (mode_r8 = '1' and cpt_libre >= 6666666) or cpt_libre = 14999999 then
                cpt_libre  <= 0;
                sync_libre <= '1';
            else
                cpt_libre <= cpt_libre + 1;
            end if;
        end if;
    end process;

    sync_ligne <= sync_libre when sw_s2(3) = '1' else sync_valid;

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
            front_ech  => sw_s2(2),
            clk_mic    => clk_mic,
            lr_sel     => lr_sel,
            pcm_data   => pcm_audio,
            sample_val => open
        );

    inst_freq : entity work.perio_metre
        port map (
            clk      => clk_100mhz,
            hyst     => hyst,
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
            sync       => sync_1200,
            sync_val   => sync_valid,   -- 1 cycle, a la fin de la synchro (+TROU_US)
            sync_image => sync_image
        );

    inst_lum : entity work.luminance
        generic map ( CLK_MHZ => 100, TROU_US => TROU_US )
        port map (
            clk      => clk_100mhz,
            raz      => rst,
            mode_r8  => mode_r8,
            sync_val => sync_ligne,     -- vraie synchro, ou fausse en mode libre
            T        => periode_us,     -- les 12 bits (avant : 10 bits -> repliement)
            data_out => pixel_gris,
            x_out    => pixel_x,
            pix_val  => pixel_we,
            line_end => line_end
        );

    ----------------------------------------------------------------------------
    -- Chaine couleur (Robot 36) : chrominance + conversion YCrCb -> RGB
    ----------------------------------------------------------------------------
    inst_chroma : entity work.chrominance
        generic map ( CLK_MHZ => 100, RETARD_US => 0 )
        port map (
            clk      => clk_100mhz,
            raz      => rst,
            sync_val => sync_ligne,
            T        => periode_us,
            lum_we   => pixel_we,
            lum_x    => pixel_x,
            lum_data => pixel_gris,
            lum_end  => line_end,
            Y        => c_Y,
            Cr       => c_Cr,
            Cb       => c_Cb,
            x_out    => c_x,
            pix_val  => c_val,
            line_end => c_end,
            paire    => open
        );

    inst_rgb : entity work.ycbcr_rgb
        port map (
            clk      => clk_100mhz,
            Y        => c_Y,
            Cr       => c_Cr,
            Cb       => c_Cb,
            x_in     => c_x,
            val_in   => c_val,
            last_in  => c_end,
            rgb      => rgb_data,
            x_out    => rgb_x,
            val_out  => rgb_we,
            last_out => rgb_end
        );

    ----------------------------------------------------------------------------
    -- Aiguillage gris / couleur
    --   gris    : pixel ecrit pendant le balayage Y, gris recopie sur R, G, B
    --   couleur : pixel ecrit pendant le balayage chroma (fin de ligne)
    ----------------------------------------------------------------------------
    ecr_we   <= rgb_we   when couleur = '1' else pixel_we;
    ecr_x    <= rgb_x    when couleur = '1' else pixel_x;
    ecr_end  <= rgb_end  when couleur = '1' else line_end;
    ecr_data <= rgb_data when couleur = '1' else
                pixel_gris(7 downto 4) & pixel_gris(7 downto 4) & pixel_gris(7 downto 4);

    ----------------------------------------------------------------------------
    -- Numero de ligne : avance a chaque fin de ligne, revient en haut apres la
    -- derniere ligne, et repart de 0 a chaque nouvelle image (en-tete VIS).
    ----------------------------------------------------------------------------
    p_ligne : process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if rst = '1' or clear_pulse = '1' or sync_image = '1' then
                y_coord <= (others => '0');
            elsif ecr_end = '1' then
                if (mode_r8 = '1' and y_coord >= 119) or y_coord = 239 then
                    y_coord <= (others => '0');
                else
                    y_coord <= y_coord + 1;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Ecriture en VRAM (320 x 240, adresse = ligne*320 + colonne)
    --   Robot 36 : 1 ecriture par pixel, en (x, y)
    --   Robot 8  : 4 ecritures par pixel (2 x 2) en (2x, 2y), (2x+1, 2y),
    --              (2x, 2y+1), (2x+1, 2y+1) -> l'image 160x120 remplit l'ecran
    -- (ecr_end arrive dans le meme cycle que le dernier ecr_we : y n'a pas
    --  encore change, le dernier pixel est donc bien ecrit sur la bonne ligne)
    ----------------------------------------------------------------------------
    p_ecriture : process(clk_100mhz)
        variable lig, col : unsigned(16 downto 0);
        variable adr      : unsigned(16 downto 0);
    begin
        if rising_edge(clk_100mhz) then
            vram_we <= '0';

            if ecr_we = '1' then
                if mode_r8 = '1' then
                    lig := shift_left(resize(y_coord, 17), 1);          -- 2y
                    col := shift_left(resize(unsigned(ecr_x), 17), 1);   -- 2x
                else
                    lig := resize(y_coord, 17);
                    col := resize(unsigned(ecr_x), 17);
                end if;
                adr := shift_left(lig, 8) + shift_left(lig, 6) + col;   -- lig*320 + col
                vram_waddr <= std_logic_vector(adr);
                vram_data  <= ecr_data;
                vram_we    <= '1';
                base_addr  <= adr;
                ecr_cnt    <= 1;
                ecr_actif  <= mode_r8;            -- 3 ecritures de plus en Robot 8

            elsif ecr_actif = '1' then
                case ecr_cnt is
                    when 1      => vram_waddr <= std_logic_vector(base_addr + 1);
                    when 2      => vram_waddr <= std_logic_vector(base_addr + 320);
                    when others => vram_waddr <= std_logic_vector(base_addr + 321);
                end case;
                vram_we <= '1';
                if ecr_cnt = 3 then
                    ecr_actif <= '0';
                else
                    ecr_cnt <= ecr_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- VRAM + VGA
    ----------------------------------------------------------------------------
    inst_vga : entity work.vga_display
        port map (
            clk          => clk_100mhz,
            rst          => rst,
            wr_addr      => vram_waddr,
            vram_data_in => vram_data,
            wr_en        => vram_we,
            clear        => clear_pulse,   -- efface en blanc
            HSYNC        => vga_hsync,
            VSYNC        => vga_vsync,
            VGA_R        => vga_R,
            VGA_G        => vga_G,
            VGA_B        => vga_B
        );

    ----------------------------------------------------------------------------
    -- Debug : LED + 7 segments
    ----------------------------------------------------------------------------
    inst_debug : entity work.debug_carte
        port map (
            clk      => clk_100mhz,
            rst      => rst,
            tick_1us => tick_1us,
            pcm      => pcm_audio,
            T        => periode_us,
            sync     => sync_1200,
            sync_val => sync_valid,
            pix_we   => pixel_we,
            ligne    => std_logic_vector(y_coord),
            led      => led,
            seg      => seg,
            an       => an
        );

end Structural;
