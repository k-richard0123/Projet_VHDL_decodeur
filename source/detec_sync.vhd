
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity detec_sync is

    generic (
        marge_compteur : integer := 8 -- Générique qqui représente la marge de tolérance du compteur de 9ms (la valeur du generic est le temps en us qui sera la différence entre 9ms et la valeur tolérée)
    );



    Port( clk: in std_logic;        
          raz: in std_logic;        
          T: in std_logic_vector(11 downto 0)  ;      
        
            sync: out std_logic;
            sync_val: out std_logic
    );




end detec_sync;


architecture Behavioral of detec_sync is


signal cnt: unsigned(19 downto 0) := to_unsigned(0,20);
signal sig_sync: std_logic := '0';

begin

    sync<=sig_sync;
                  


process(clk, raz)
    begin
        
        if (raz='1') then
            sig_sync<='0';
          
        else
                 if(clk'event and clk='1') then
                    
                 
                    if (UNSIGNED(T)>=800 and unsigned(T)<=870) then --si on se trouve dans la plage des 1200Hz de synchro alors on envoie une impulsion de synchro verticale
                        sig_sync<='1';
                       
                        
                       
                    else
                        sig_sync<='0';
                       
                  
                  
                     end if;      
                end if; 
        end if;
    end process;
    
    
    
    
    
process(clk,raz)--process qui permet de dire si on à les  9ms-marge_compteur  à 1200Hz
 
begin
    if(raz='1') then
        sync_val<='0';
        cnt<= (others => '0');
        
    else 

        
                 if(clk'event and clk='1') then
                    
                 
                    if ((cnt= 900000 - marge_compteur) and sig_sync='1') then 
                            sync_val<='1';
                            cnt<=cnt+1;
                    else
                        sync_val<='0';
                        cnt<= (others => '0');
                    end if;
                 end if;
   end if;
end process;


end Behavioral;
