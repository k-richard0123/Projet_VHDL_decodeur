library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity chrominance is
    generic (
        fclk : integer := 100 -- Fréquence de l'horloge système en MHz
    );
    Port ( 
        clk      : in  std_logic;
        raz      : in  std_logic;
        
       
        addr     : in  std_logic_vector(9 downto 0);  -- Période signal en µs 
        
     
        sync_1200: in  std_logic; -- '1' si le Zero-Crossing détecte ~1200 Hz
        
        -- Sorties stockées (les 3 valeurs pour le pixel en cours)
        Y   : out std_logic_vector(7 downto 0); -- Luminance
        Cr   : out std_logic_vector(7 downto 0); -- Rouge (R-Y)
        Cb   : out std_logic_vector(7 downto 0); -- Bleu (B-Y)
        
        -- Signal de validation : '1' pendant 1 cycle quand les 3 valeurs Y,Cr,Cb sont prêtes
        pixel_valid : out std_logic 
    );
end chrominance;

architecture Behavioral of chrominance is


    --  Définition des états de la fsm
    type state_type is (att_sync, palier_sync, scan_y, sep, palier_chrom, scan_c);
    signal state : state_type := att_sync;


    signal timer_cnt : integer range 0 to 10000000 := 0; -- Compteur de temps général
    signal pixel_idx : integer range 0 to 320 := 0;      -- Compteur de pixels (0 à 319)
    signal ligne_paire : boolean := true;               -- Mémoire de la parité de la ligne


    signal reg_Y  : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_Cr : std_logic_vector(7 downto 0) := (others => '0');
    signal reg_Cb : std_logic_vector(7 downto 0) := (others => '0');

    --ROM de gris
    type rom_type is array (434 to 666) of integer range 0 to 255;
    constant ROM_DATA : rom_type := (
        255, 253, 253, 251, 251, 248, 248, 246, 246, 244, 244, 242, 242, 240, 240, 237,
        237, 235, 235, 233, 233, 231, 231, 229, 229, 226, 226, 224, 224, 222, 222, 220,
        220, 218, 218, 215, 215, 213, 213, 211, 211, 209, 209, 207, 207, 204, 204, 202,
        202, 200, 200, 198, 198, 196, 196, 193, 193, 191, 191, 189, 189, 187, 187, 185,
        185, 182, 182, 180, 180, 178, 178, 176, 176, 174, 174, 171, 171, 169, 169, 167,
        167, 165, 165, 163, 163, 160, 160, 158, 158, 156, 156, 154, 154, 152, 152, 149,
        149, 147, 147, 145, 145, 143, 143, 141, 141, 138, 138, 136, 136, 134, 134, 132,
        132, 130, 130, 128, 128, 125, 125, 123, 123, 121, 121, 119, 119, 117, 117, 114,
        114, 112, 112, 110, 110, 108, 108, 106, 106, 103, 103, 101, 101,  99,  99,  97,
         97,  95,  95,  92,  92,  90,  90,  88,  88,  86,  86,  84,  84,  81,  81,  79,
         79,  77,  77,  75,  75,  73,  73,  70,  70,  68,  68,  66,  66,  64,  64,  62,
         62,  59,  59,  57,  57,  55,  55,  53,  53,  51,  51,  48,  48,  46,  46,  44,
         44,  42,  42,  40,  40,  37,  37,  35,  35,  33,  33,  31,  31,  29,  29,  26,
         26,  24,  24,  22,  22,  20,  20,  18,  18,  15,  15,  13,  13,  11,  11,   9,
          9,   7,   7,   4,   4,   2,   2,   0,   0
    );
    signal niv_gris : std_logic_vector(7 downto 0);

begin


    Y  <= reg_Y;
    Cr <= reg_Cr;
    Cb <= reg_Cb;

    -- Extraction du niveau de gris en continu à partir de la Période (addr)
    process(clk)
        variable p_idx : unsigned(9 downto 0);
    begin
        if rising_edge(clk) then
            p_idx := unsigned(addr);
            if p_idx < 434 then 
                niv_gris <= std_logic_vector(to_unsigned(255, 8)); 
            elsif p_idx > 666 then
                niv_gris <= std_logic_vector(to_unsigned(0, 8));   
            else
                niv_gris <= std_logic_vector(to_unsigned(ROM_DATA(to_integer(p_idx)), 8));
            end if;
        end if;
    end process;


    -- fsm de décodage
    process(clk, raz)
        variable p_idx_sep : unsigned(9 downto 0);
    begin
        if raz = '1' then
            state <= att_sync;
            timer_cnt <= 0;
            pixel_idx <= 0;
            pixel_valid <= '0';
            ligne_paire <= true;
            
        elsif rising_edge(clk) then
            pixel_valid <= '0'; -- Impulsion d'un cycle par défaut
            
            case state is
            
                --Attente du top de départ (1200 Hz pendant ~9 ms)
                when att_sync =>
                    if sync_1200 = '1' then
                        timer_cnt <= timer_cnt + 1;
                        -- On valide si on a eu au moins 5 ms de 1200 Hz
                        if timer_cnt >= (5000 * fclk) then
                            state <= palier_sync;
                            timer_cnt <= 0;
                        end if;
                    else
                        timer_cnt <= 0;
                    end if;

                --Palier noir de stabilisation (1500 Hz pendant 3 ms)
                when palier_sync =>
                    timer_cnt <= timer_cnt + 1;
                    if timer_cnt >= 3000   * fclk then
                        state <= scan_y;
                        timer_cnt <= 0;
                        pixel_idx <= 0;
                    end if;

                -- balayage de la luminance Y (320 pixels, 275 us chacun)
                when scan_y =>
                    timer_cnt <= timer_cnt + 1;
                    if timer_cnt >= 275    * fclk then
                        timer_cnt <= 0;
                        
                        -- On échantillonne le niveau de gris actuel pour Y
                        reg_Y <= niv_gris;
                        
                        pixel_idx <= pixel_idx + 1;
                        if pixel_idx = 319 then
                            state <= sep;
                            timer_cnt <= 0;
                        end if;
                    end if;

                -- Impulsion de séparation (4.5 ms) pour deviner Cr ou Cb
                when sep =>
                    timer_cnt <= timer_cnt + 1;
                    
                    -- On échantillonne la fréquence au milieu du séparateur (vers 2 ms)
                    if timer_cnt = (2000 * fclk) then
                        p_idx_sep := unsigned(addr);
                        -- Si la période est > 600 us (~1500 Hz Noir), c'est une ligne Paire (Rouge)
                        if p_idx_sep > 600 then
                            ligne_paire <= true;
                        else
                            ligne_paire <= false;
                        end if;
                    end if;
                    
                    if( timer_cnt >= 4500*fclk) then
                        state <= palier_chrom;
                        timer_cnt <= 0;
                    end if;

                --palier neutre de chrominance (1900 Hz pendant 1.5 ms)
                when palier_chrom =>
                    timer_cnt <= timer_cnt + 1;
                    if (timer_cnt >= 1500   * fclk) then
                        state <= scan_c;
                        timer_cnt <= 0;
                        pixel_idx <= 0;
                    end if;

                -- Balayage de la chrominance (320 pixels, 137 us chacun)
                when scan_c =>
                    timer_cnt <= timer_cnt + 1;
                    if timer_cnt >= 137    * fclk then
                        timer_cnt <= 0;
                        
                        -- On affecte la couleur lue au bon registre selon la parité de la ligne
                        if ligne_paire then
                            reg_Cr <= niv_gris;
                        else
                            reg_Cb <= niv_gris;
                        end if;
                        
                        -- Le pixel complet (Y + Cr + Cb) est prêt à être écrit en mémoire vram
                        pixel_valid <= '1';
                        
                        pixel_idx <= pixel_idx + 1;
                        if pixel_idx =319 then
                            state <= att_sync; -- Fin de ligne, on attend la synchro suivante
                            timer_cnt <= 0;
                        end if;
                    end if;

            end case;
        end if;
    end process;

end architecture Behavioral;