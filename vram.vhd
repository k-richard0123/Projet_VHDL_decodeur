--------------------------------------------------------------------------------
-- Etage 3 : VRAM 320x240 pixels, 8 bits (niveau de gris)
--
--  * Memoire double port inferee en Block RAM (ecriture port A, lecture port B)
--  * Meme horloge clk (100 MHz) pour les deux ports
--  * Contenu initial = noir (ecran noir au demarrage)
--  * Entree clear : impulsion d'1 cycle -> la VRAM est remise a 0 en
--    76 800 cycles (~0,77 ms). Pendant l'effacement, wr_en est ignore.
--  * Lecture synchrone : pixel_out est valide 1 cycle apres rd_addr
--
--  Adresse = ligne * 320 + colonne   (0 .. 76 799, sur 17 bits)
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vram is
    Port ( clk          : in  std_logic;
           rst          : in  std_logic;                      -- reset synchrone, actif a '1'

           -- Port A : ecriture (cote FSM / Etage 2)
           wr_addr      : in  std_logic_vector(16 downto 0);
           vram_data_in : in  std_logic_vector(7 downto 0);
           wr_en        : in  std_logic;
           clear        : in  std_logic;                      -- impulsion : efface toute l'image

           -- Port B : lecture (cote controleur VGA)
           rd_addr      : in  std_logic_vector(16 downto 0);
           pixel_out    : out std_logic_vector(7 downto 0)
         );
end vram;

architecture Behavioral of vram is

    constant NB_PIXELS : integer := 320 * 240;                -- 76 800

    type ram_t is array (0 to NB_PIXELS - 1) of std_logic_vector(7 downto 0);
    signal ram : ram_t := (others => (others => '0'));        -- init = noir

    attribute ram_style : string;
    attribute ram_style of ram : signal is "block";

    -- Sequenceur d'effacement
    signal clr_active : std_logic := '0';
    signal clr_cnt    : unsigned(16 downto 0) := (others => '0');

    -- Signaux effectivement appliques au port d'ecriture
    signal we_int   : std_logic;
    signal addr_int : unsigned(16 downto 0);
    signal data_int : std_logic_vector(7 downto 0);

begin

    ----------------------------------------------------------------------------
    -- Sequenceur d'effacement : parcourt toutes les adresses en ecrivant 0
    ----------------------------------------------------------------------------
    p_clear : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                clr_active <= '0';
                clr_cnt    <= (others => '0');
            elsif clear = '1' then                             -- (re)demarre l'effacement
                clr_active <= '1';
                clr_cnt    <= (others => '0');
            elsif clr_active = '1' then
                if clr_cnt = to_unsigned(NB_PIXELS - 1, 17) then
                    clr_active <= '0';
                    clr_cnt    <= (others => '0');
                else
                    clr_cnt <= clr_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Multiplexage du port d'ecriture : effacement prioritaire sur l'ecriture
    ----------------------------------------------------------------------------
    addr_int <= clr_cnt                  when clr_active = '1' else unsigned(wr_addr);
    data_int <= (others => '0')          when clr_active = '1' else vram_data_in;
    we_int   <= '1'                      when clr_active = '1' else
                '1'                      when (wr_en = '1' and unsigned(wr_addr) < NB_PIXELS) else
                '0';

    ----------------------------------------------------------------------------
    -- Memoire : ecriture port A, lecture port B (les deux synchrones)
    ----------------------------------------------------------------------------
    p_ram : process(clk)
    begin
        if rising_edge(clk) then
            if we_int = '1' then
                ram(to_integer(addr_int)) <= data_int;
            end if;
            if unsigned(rd_addr) < NB_PIXELS then
                pixel_out <= ram(to_integer(unsigned(rd_addr)));
            else
                pixel_out <= (others => '0');
            end if;
        end if;
    end process;

end Behavioral;