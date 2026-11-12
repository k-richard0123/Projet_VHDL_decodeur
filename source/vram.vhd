--------------------------------------------------------------------------------
-- VRAM 320x240 pixels, 8 bits (niveau de gris)
--
--  (ecriture port A, lecture port B)
--  init ecran noir 
--  Adresse = ligne * 320 + colonne   (0 .. 76 799, sur 17 bits)
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vram is
    Port ( clk : in  std_logic;
           rst : in  std_logic;

          --coté FSM
           wr_addr      : in  std_logic_vector(16 downto 0);
           vram_data_in : in  std_logic_vector(7 downto 0);
           wr_en        : in  std_logic;
           clear        : in  std_logic;

           --cote controleur VGA
           rd_addr      : in  std_logic_vector(16 downto 0);
           pixel_out    : out std_logic_vector(7 downto 0)
         );
end vram;

architecture Behavioral of vram is

    constant NB_PIXELS : integer := 320 * 240;  --lignes fois colonens
    type ram_t is array (0 to NB_PIXELS - 1) of std_logic_vector(7 downto 0);
    signal ram : ram_t := (others => (others => '0'));        -- init = noir (0 c'est noir et 255 c'est blanc)
    attribute ram_style : string;
    attribute ram_style of ram : signal is "block";
    signal clr_actif : std_logic := '0';
    signal clr_cnt    : unsigned(16 downto 0) := (others => '0');
    signal we_int   : std_logic;
    signal addr_int : unsigned(16 downto 0);
    signal data_int : std_logic_vector(7 downto 0);

begin

-- là on remet le signal clear à '1' pendant 76 800 cycles d'horloge pour effacer l'écran
    p_clear : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                clr_actif <= '0';
                clr_cnt    <= (others => '0');
            elsif clear = '1' then     
                clr_actif <= '1';
                clr_cnt    <= (others => '0');
            elsif clr_actif = '1' then
                if clr_cnt = to_unsigned(NB_PIXELS - 1, 17) then
                    clr_actif <= '0';
                    clr_cnt    <= (others => '0');
                else
                    clr_cnt <= clr_cnt + 1;
                end if;
            end if;
        end if;
    end process;

--?????????
    addr_int <= clr_cnt when clr_actif = '1' else unsigned(wr_addr);
    data_int <= (others => '0') when clr_actif = '1' else vram_data_in;
    we_int   <= '1' when clr_actif = '1' else
                 '1' when (wr_en = '1' and unsigned(wr_addr) < NB_PIXELS) else
                '0';

--???????
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