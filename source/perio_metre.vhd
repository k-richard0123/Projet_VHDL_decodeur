
------------------------------------------------------------------------------

--les conditions du période-metre sont:
--signal centré sur 0
--gamme de fréquence entre 1200 et 2300 Hz




--L'ensemble de l'explication sur les 1/2 T, bandeaux,... peut sembler compliquer mais ce n'est qu'un principe d'hysteresis 
--qui se comprend tres facilement avec un dessin tel que celui ci




--                   #####                                    .---.
--                ###     ###                                /     \
--              ##           ##                             /       \
-- +hyst ------#---------------#---------------------------*---------\------- (Seuil haut : +512)
--            /                 #                         *           \
--           /                   #                       *             \
--     0 ---/---------------------#---------------------*---------------\---- (Axe 0)
--                                 #                   *
--                                  #                 *
-- -hyst ----------------------------#---------------*----------------------- (Seuil bas  : -512)
--                                    *             *
--                                     **         **
--                                       ***   ***
--                                          ***
-- 
--          |<------- cnt_hys = '0' ------->|<------ cnt_hys = '1' ----->|
--          |        (Mesure de T/2)        |       (Mesure de T/2)      |





------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity perio_metre is
 Port( sig_in: in std_logic_vector(15 downto 0);
        clk_1: in std_logic; -- clk=1MHz
        raz: in std_logic;
        
        T: out std_logic_vector(11 downto 0)        
        

    );
end perio_metre;

architecture Behavioral of perio_metre is

    constant T_clk: integer := 100; --T=1us
    constant hyst : signed(15 downto 0) := to_signed(512,16); --valeur de la bande d'hysteresis qui permet de palier au pb du signal bruité, le 512 est à ajuster si jamais
    signal cnt: unsigned(9 downto 0) := to_unsigned(0,10); --cnt qui permet de savoir combien de périodes de 1us comptées entre chaque demi période du signal
    signal cnt_hys: std_logic := '0'; --si =0 alors au dessus de +hyst, si =1 alors en dessous de -hyst
 
    signal sig_audio: signed(15 downto 0);
    

begin


process(clk_1,raz)
    begin
           
           if(raz='1') then --(Ré)Initialisations
           
                sig_audio <= (others => '0');
                T         <= (others => '0');
                cnt       <= (others => '0');
                cnt_hys   <= '0';
                
                
           else
                 if(clk_1'event and clk_1='1') then
                    sig_audio <= signed(sig_in); --on échantillonne le signal audio entrant
                    
                    if(cnt_hys = '0') then   --si on est au sur la section [+hyst;-hyst] i.e la partie montante du signal...
                        
                        if(sig_audio >= -hyst) then --... et que le signal est supérieur à -hyst (donc croit)
                        
                            cnt_hys <= '0'; --alors on reste dans le bandeau 
                            cnt <= cnt + 1; --on incrémente le compteur
                        
                        else --quand on sort du bandeau
                        
                            
                       
                            T <= std_logic_vector(to_unsigned( integer(2 * TO_INTEGER(cnt+1)),12)); --le calcul de T se fait par le nombre de fois (valeur de cnt)
                            -- où l'on a compté une période de clk_1 ce qui donne cnt*1MHz mais cela est la 1/2 periode =>T= 2*cnt*1MHz mais la valeur bien choisie de 1MHz permet de dire T=2*cnt avec T en us
                            --De plus, le cnt+1 permet de palier à un cycle d'horloge de retard. NOTEZ que la periode affichée sera TJR paires mais les incertitudes 
                            --de qlq us ne posent pas tant de soucis que ça pour notre projet.
                        
                        
                            cnt_hys <='1'; --puisqu'on sort du 1e bandeau alors on passe dans le cas [-hyst;+hyst] mod(qlq chose) Finalement on passe dans la 2e demi période
                            cnt <= (others => '0'); --pour compter la 2e 1/2 T alors rst cnt
                        end if;
                        
                       
                     
                     
                     
                     
                     
                    elsif(cnt_hys = '1') then --cas de la 2e 1/2 T
                    
                        if(sig_audio <= hyst) then --meme raisonnement que tt à l'heure mais dans la 2e 1/2 T
                        
                            cnt_hys <= '1';
                            cnt <= cnt + 1;
                        
                        else 
                        
                            
                       
                             T <= std_logic_vector(to_unsigned( integer(2 * TO_INTEGER(cnt+1)),12));
                        
                            cnt_hys <='0';
                            cnt <= (others => '0');
                            
                        end if;
                        
                    end if;
                    
                  end if;
               
              end if;

end process;
     
        


end Behavioral;
