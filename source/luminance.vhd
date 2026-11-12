library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity luminance is

    generic (
        marge_compteur : integer := 8 -- Générique qqui représente la marge de tolérance du compteur de 0.275 ms/pix (la valeur du generic est le temps en us qui sera la différence entre 9ms et la valeur tolérée)
    );
    
    
    port (
        clk      : in  std_logic;
        raz :in std_logic;
        addr     : in  std_logic_vector(9 downto 0); -- Période en us (0 à 1023)
        
        data_out : out std_logic_vector(7 downto 0) ; -- Niveau de gris (0 à 255)
        pix_val:out std_logic
    );
end entity luminance;

architecture rtl of luminance is

signal cnt: unsigned(23 downto 0) := to_unsigned(0,24);
signal sig_pix_val: std_logic := '0';

    -- La plage utile de la période définie dans le fichier va de 434 us à 666 us.
    -- On crée un tableau qui ne stocke que cette plage pour économiser de l'espace.
    type rom_type is array (434 to 666) of integer range 0 to 255;
    
    -- Pour les périodes impaires non définies dans l'Excel (ex: 665), 
    -- la valeur a été interpolée sur la période paire supérieure (ex: 666).
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

begin

    process(clk)
        variable p_idx : unsigned(9 downto 0);
    begin
        if rising_edge(clk) then
            p_idx := unsigned(addr);
            
            -- Gestion des bornes pour éviter une erreur d'indexation
            if p_idx < 434 then
                data_out <= std_logic_vector(to_unsigned(255, 8)); -- Saturation au gris max pour les périodes courtes
            elsif (p_idx > 666 )then
                data_out <= std_logic_vector(to_unsigned(0, 8));   -- Saturation au gris min pour les périodes longues
            else
                data_out <= std_logic_vector(to_unsigned(ROM_DATA(to_integer(p_idx)), 8));
            end if;
        end if;
    end process;
    
    
    
  process(clk,raz)--process qui permet de dire si on à les  275us-marge_compteur  
 
begin
    if(raz='1') then
        pix_val<='0';
        cnt<= (others => '0');
        
    else 

        
                 if(clk'event and clk='1') then
                     cnt<=cnt+1;
                 
                    if (cnt= 275000000 - marge_compteur) then 
                            pix_val<='1';
                            cnt<= (others => '0');
                    else
                        pix_val<='0';
                        
                    end if;
                 end if;
   end if;
end process;

end architecture rtl;