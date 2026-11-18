library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


--multiplexeur placé entre la machine d'état qui calcule la chrominance et qui laisse passer ou non que le gris ou la couleur (juste avant la vram)
-- SUR 1 PIXEL
entity multiplex_gris_couleur is
Port ( sw1:in std_logic;
       
        gris   : in std_logic_vector(7 downto 0); -- Luminance
        Cr   : in std_logic_vector(7 downto 0); -- Rouge (R-Y)
        Cb   : in std_logic_vector(7 downto 0); -- Bleu (B-Y)
        
       Cr_out: out std_logic_vector(7 downto 0)  ;
       Cb_out: out std_logic_vector(7 downto 0)  ;
       gris_out: out std_logic_vector(7 downto 0)        



 );
end multiplex_gris_couleur;

architecture Behavioral of multiplex_gris_couleur is
begin
    
--gris passe au moins tout le temps
    gris_out <= gris;

    -- Les couleurs passent si sw1 = '1', sinon on force à 0 
    Cr_out <= Cr when sw1 = '1' else (others => '0');
    Cb_out <= Cb when sw1 = '1' else (others => '0');
 
        
end Behavioral;
