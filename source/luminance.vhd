
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity luminance is

  generic (
        marge_compteur : integer := 8 -- Générique qqui représente la marge de tolérance du compteur de 0.275 ms/pix (la valeur du generic est le temps en us qui sera la différence entre 9ms et la valeur tolérée)
    );



  Port (clk: in std_logic;        
        raz: in std_logic;        
        T: in std_logic_vector(11 downto 0);
        
        pix_val:out std_logic;
        niv_gris: out std_logic_vector(7 downto 0)
  
         );
end luminance;

architecture Behavioral of luminance is


signal cnt: unsigned(23 downto 0) := to_unsigned(0,24);
signal sig_pix_val: std_logic := '0';

begin


process(clk,raz)
    begin
        
        if (raz='1') then
            niv_gris<=(others => '0');
          
        else
                 if(clk'event and clk='1') then

                       niv_gris <= std_logic_vector(to_unsigned((((50000000 / to_integer(unsigned(T))) - 1500) * 328) / 1024, 8));
                  



        end if;
    end if;
end process;




process(clk,raz)--process qui permet de dire si on à les  0.275ms-marge_compteur  
 
begin
    if(raz='1') then
        pix_val<='0';
        cnt<= (others => '0');
        
    else 

        
                 if(clk'event and clk='1') then
                     cnt<=cnt+1;
                 
                    if (cnt= 8800000 - marge_compteur) then 
                            pix_val<='1';
                           
                    else
                        pix_val<='0';
                        cnt<= (others => '0');
                    end if;
                 end if;
   end if;
end process;

end Behavioral;
