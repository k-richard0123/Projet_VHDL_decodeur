library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_multiplex_gris_couleur is
end tb_multiplex_gris_couleur;

architecture behavior of tb_multiplex_gris_couleur is

    -- Signaux d'entrée
    signal sw1  : std_logic := '0';
    signal gris : std_logic_vector(7 downto 0) := (others => '0');
    signal Cr   : std_logic_vector(7 downto 0) := (others => '0');
    signal Cb   : std_logic_vector(7 downto 0) := (others => '0');

    -- Signaux de sortie
    signal Cr_out   : std_logic_vector(7 downto 0);
    signal Cb_out   : std_logic_vector(7 downto 0);
    signal gris_out : std_logic_vector(7 downto 0);

begin

    -- Instanciation du composant (Device Under Test)
    uut: entity work.multiplex_gris_couleur
        port map (
            sw1      => sw1,
            gris     => gris,
            Cr       => Cr,
            Cb       => Cb,
            Cr_out   => Cr_out,
            Cb_out   => Cb_out,
            gris_out => gris_out
        );

    -- Processus de stimulus pour tester toutes les conditions
    stim_proc: process
    begin
        -- Test 1 : sw1 = '0' (Mode Noir et Blanc)
        -- Attendu : gris_out = x"AA", Cr_out = x"00", Cb_out = x"00"
        sw1  <= '0';
        gris <= x"AA";
        Cr   <= x"BB";
        Cb   <= x"CC";
        wait for 20 ns;

        -- Test 2 : sw1 = '1' (Mode Couleur)
        -- Attendu : gris_out = x"AA", Cr_out = x"BB", Cb_out = x"CC"
        sw1  <= '1';
        wait for 20 ns;

        -- Test 3 : Changement dynamique des signaux pendant sw1 = '1'
        -- Attendu : Les sorties suivent immédiatement les nouvelles entrées
        gris <= x"11";
        Cr   <= x"22";
        Cb   <= x"33";
        wait for 20 ns;

        -- Test 4 : Retour à sw1 = '0' avec changement du gris
        -- Attendu : gris_out suit la nouvelle valeur, Cr_out et Cb_out retombent à 0
        sw1  <= '0';
        gris <= x"FF";
        Cr   <= x"44";
        Cb   <= x"55";
        wait for 20 ns;

        -- Fin de la simulation
        assert false report "Simulation terminée avec succès." severity note;
        wait;
    end process;

end behavior;