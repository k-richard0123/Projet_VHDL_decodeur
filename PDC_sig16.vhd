library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;




entity PDC_sig16 is
    Port (
        clk_100mhz: in  STD_LOGIC; -- Horloge système 100 MHz
        reset: in  STD_LOGIC; -- Reset synchrone
        data_pdm: in  STD_LOGIC; -- Données PDM
        clk_mic: out STD_LOGIC; -- Horloge micro PDM
        lr_sel: out STD_LOGIC; -- Sélection canal L/R
        pcm_data: out STD_LOGIC_VECTOR(15 downto 0); -- Sortie PCM 16 bits
        sample_val: out STD_LOGIC -- Signal à '1' un cycle lorsque PCM est prêt
    );

end PDC_sig16;






architecture Behavioral of PDC_sig16 is

    signal compteur_div: integer range 0 to 20 := 0;
    signal internal_clk_mic: std_logic := '0';
    constant DECIMATION_FACTOR: integer := 64;
    signal compteur_decimation: integer range 0 to DECIMATION_FACTOR - 1 := 0;
    signal somme_uns: unsigned(15 downto 0) := (others => '0');

begin




    p_clk_gen : process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if reset = '1' then
                compteur_div <= 0;
                internal_clk_mic <= '0';
            elsif compteur_div = 20 then -- 100 MHz / (2 * 21) ≈ 2.38 MHz
                internal_clk_mic <= not internal_clk_mic;
                compteur_div <= 0;
            else
                compteur_div <= compteur_div + 1;
            end if;
        end if;
    end process;




    clk_mic <= internal_clk_mic;
    lr_sel <= '0'; -- Fixe le canal à gauche pour cet exemple, peut être modifié selon les besoins)





    p_decimation : process(internal_clk_mic)
    begin
        if rising_edge(internal_clk_mic) then
            if reset = '1' then
                compteur_decimation <= 0;
                somme_uns <= (others => '0');
                pcm_data <= (others => '0');
                sample_val <= '0';
            else
                if compteur_decimation = DECIMATION_FACTOR - 1 then
                    pcm_data <= std_logic_vector(somme_uns & "00"); -- Ajustement sur 16 bits
                    somme_uns <= (others => '0');
                    compteur_decimation <= 0;
                    sample_val <= '1'; -- Impulsion d'un cycle d'horloge mic
                else
                    if data_pdm = '1' then
                        somme_uns <= somme_uns + 1;
                    end if;
                    compteur_decimation <= compteur_decimation + 1;
                    sample_val <= '0';
                end if;
            end if;
        end if;
    end process;

end Behavioral;