--clk_100mhz : horloge système de référence de la carte (100 MHz).

--clk_mic : horloge d'échantillonnage fournie au micro PDM (~2,4 MHz).

--compteur_div : compteur permettant de diviser la fréquence 100 MHz pour obtenir clk_mic.

--data_pdm : flux de données 1 bit issu du microphone.

--somme_uns : accumulateur comptant le nombre de bits à 1 sur une fenêtre de décimation.

--compteur_decimation : compteur rythmant la taille de la fenêtre de décimation.

--DECIMATION_FACTOR : constante fixant le rapport de sous-échantillonnage (ex. 64 ou 128).

--pcm_output : échantillon audio multi-bits (PCM) converti.

--sample_ready : indicateur (flag) signalant qu'un nouvel échantillon PCM est disponible.

--compteur_periode : compteur mesurant le nombre de cycles d'échantillonnage entre deux fronts.

--SEUIL_ZERO : valeur de référence pour détecter le passage par zéro du signal.

--pcm_output_old : valeur de l'échantillon précédent, indispensable pour détecter le changement de signe.

--periode_mesuree : valeur finale de la période du signal sonore stockée après détection.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;

entity PDC_Tsig is
    Port ( clk_100mhz : in STD_LOGIC;
           data_pdm : in STD_LOGIC;
           clk_mic : out STD_LOGIC;
           pcm_output : out STD_LOGIC_VECTOR(15 downto 0);
           sample_ready : out STD_LOGIC;
           periode_mesuree : out STD_LOGIC_VECTOR(15 downto 0));
end PDC_Tsig;






architecture Behavioral of PDC_Tsig is

begin

process(clk_100mhz)
begin
    if rising_edge(clk_100mhz) then
        if compteur_div = 20 then
            clk_mic <= not clk_mic;
            compteur_div <= (others => '0');
        else
            compteur_div <= compteur_div + 1;
        end if;
    end if;
end process;






process(clk_mic)
begin
    if rising_edge(clk_mic) then
        if compteur_decimation=DECIMATION_FACTOR then
            pcm_output <= somme_uns;
            sample_ready <= '1';
            somme_uns <= (others => '0');
            compteur_decimation <= (others => '0');
        else
            if data_pdm = '1' then
                somme_uns <= somme_uns + 1;
            end if;
            compteur_decimation <= compteur_decimation +1;
            sample_ready <= '0';
        end if;
    end if;
end process;




