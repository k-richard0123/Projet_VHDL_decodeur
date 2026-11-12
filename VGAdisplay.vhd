--------------------------------------------------------------------------------
-- Etages 3 + 4 : VRAM + controleur VGA
-- A connecter a l'Etage 2 (wr_addr, vram_data_in, wr_en, clear)
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity vga_display is
    Port ( clk          : in  std_logic;                        -- 100 MHz
           rst          : in  std_logic;                        -- actif a '1'

           -- Cote Etage 2
           wr_addr      : in  std_logic_vector(16 downto 0);
           vram_data_in : in  std_logic_vector(7 downto 0);
           wr_en        : in  std_logic;
           clear        : in  std_logic;                        -- impulsion 1 cycle : nouvelle image

           -- Cote connecteur VGA
           HSYNC        : out std_logic;
           VSYNC        : out std_logic;
           VGA_R        : out std_logic_vector(3 downto 0);
           VGA_G        : out std_logic_vector(3 downto 0);
           VGA_B        : out std_logic_vector(3 downto 0)
         );
end vga_display;

architecture Structural of vga_display is

    signal rd_addr   : std_logic_vector(16 downto 0);
    signal pixel_out : std_logic_vector(7 downto 0);

begin

    u_vram : entity work.vram
        port map ( clk          => clk,
                   rst          => rst,
                   wr_addr      => wr_addr,
                   vram_data_in => vram_data_in,
                   wr_en        => wr_en,
                   clear        => clear,
                   rd_addr      => rd_addr,
                   pixel_out    => pixel_out );

    u_vga : entity work.vga_controller
        port map ( clk       => clk,
                   rst       => rst,
                   rd_addr   => rd_addr,
                   pixel_out => pixel_out,
                   HSYNC     => HSYNC,
                   VSYNC     => VSYNC,
                   VGA_R     => VGA_R,
                   VGA_G     => VGA_G,
                   VGA_B     => VGA_B );

end Structural;