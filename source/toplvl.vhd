library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_sstv is
    Port (
        clk_100mhz : in  std_logic;
        btn_reset  : in  std_logic; 
        btn_clear  : in  std_logic; 
        
     
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

    signal rst_actif_haut : std_logic;
    signal clk_1mhz  : std_logic := '0';
    signal clk_div   : integer range 0 to 49 := 0;

  
    signal pcm_audio   : std_logic_vector(15 downto 0);
    signal sample_val  : std_logic;
    

    signal periode_us  : std_logic_vector(11 downto 0);
    
   
    signal sync_valid  : std_logic;
    

    signal x_coord     : unsigned(8 downto 0) := (others => '0'); -- 0 à 319
    signal y_coord     : unsigned(7 downto 0) := (others => '0'); -- 0 à 239
    signal vram_waddr  : std_logic_vector(16 downto 0);
    
    
    signal pixel_gris  : std_logic_vector(7 downto 0);
    signal pixel_we    : std_logic; 
begin

rst_actif_haut <= not btn_reset;

    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if btn_reset = '1' then
                clk_div  <= 0;
                clk_1mhz <= '0';
            elsif clk_div = 49 then
                clk_div  <= 0;
                clk_1mhz <= not clk_1mhz;
            else
                clk_div  <= clk_div + 1;
            end if;
        end if;
    end process;


    inst_mic : entity work.PDC_sig16
        port map (
            clk_100mhz => clk_100mhz,
            reset      => rst_actif_haut,
            data_pdm   => data_pdm,
            clk_mic    => clk_mic,
            lr_sel     => lr_sel,
            pcm_data   => pcm_audio,
            sample_val => sample_val
        );

    inst_freq : entity work.perio_metre
        port map (
            sig_in     => pcm_audio,
            clk_1      => clk_1mhz,
            raz        => btn_reset,
            T          => periode_us
        );

    inst_sync : entity work.detec_sync
        generic map (
            marge_compteur => 8 -- marge en us
        )
        port map (
            clk        => clk_1mhz,
            raz        => btn_reset,
            T          => periode_us,
            sync       => open,       -- Le signal interne sig_sync n'est pas utilisé ici
            sync_val   => sync_valid  -- '1' quand le balayage de la nouvelle ligne doit commencer
        );


    inst_lum : entity work.luminance
        generic map (
            marge_compteur => 8 
        )
        port map (
            clk        => clk_100mhz,
            raz        => btn_reset,
            addr       => periode_us(9 downto 0), -- On ne garde que les 10 bits de poids faible utiles
            data_out   => pixel_gris,
            pix_val    => pixel_we -- '1' toutes les 275 us
        );


    -- Le module 'luminance' nous dit *quand* un pixel est prêt (pixel_we).
    -- Le module 'detec_sync' nous dit *quand* une nouvelle ligne commence (sync_valid).
    -- Il faut combiner les deux pour calculer l'adresse VRAM !
    
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if btn_reset = '1' or btn_clear = '1' then
                x_coord <= (others => '0');
                y_coord <= (others => '0');
                
            -- Nouvelle ligne détectée : On ramène le pinceau tout à gauche (X=0)
            -- et on descend d'une ligne (Y=Y+1)
            elsif sync_valid = '1' then
                x_coord <= (others => '0');
                if y_coord = 239 then
                    y_coord <= (others => '0'); -- Retour en haut si image terminée
                else
                    y_coord <= y_coord + 1;
                end if;
                
            -- Nouveau pixel reçu : On avance le pinceau d'une case vers la droite (X=X+1)
            elsif pixel_we = '1' then
                if x_coord < 319 then
                    x_coord <= x_coord + 1;
                end if;
            end if;
        end if;
    end process;

    -- Calcul mathématique de l'adresse linéaire absolue (Addr = Y * 320 + X) pour la VRAM
    -- L'adresse est sur 17 bits. 320 = 256 + 64.
    vram_waddr <= std_logic_vector(shift_left(resize(y_coord, 17), 8) + 
                                   shift_left(resize(y_coord, 17), 6) + 
                                   resize(x_coord, 17));


    inst_vga : entity work.vga_display
        port map (
            clk          => clk_100mhz,
            rst          => btn_reset,
            
            -- Écriture (Pilotée par notre gestionnaire de coordonnées C.)
            wr_addr      => vram_waddr,
            vram_data_in => pixel_gris,
            wr_en        => pixel_we,
            clear        => btn_clear, -- Permet d'effacer l'écran en un clin d'œil
            
            -- Lecture (Connecteur physique VGA)
            HSYNC        => vga_hsync,
            VSYNC        => vga_vsync,
            VGA_R        => vga_R,
            VGA_G        => vga_G,
            VGA_B        => vga_B
        );

end Structural;