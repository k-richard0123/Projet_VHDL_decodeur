library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench du multiplexeur gris/couleur (A METTRE DANS "Simulation Sources")
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

    stim_proc: process
    begin
        -- Test 1 : sw1 = '0' (Mode Noir et Blanc) -> chroma neutre x"80"
        sw1  <= '0';
        gris <= x"AA";
        Cr   <= x"BB";
        Cb   <= x"CC";
        wait for 20 ns;
        assert gris_out = x"AA" and Cr_out = x"80" and Cb_out = x"80"
            report "Test 1 (mode gris) en echec" severity error;

        -- Test 2 : sw1 = '1' (Mode Couleur)
        sw1  <= '1';
        wait for 20 ns;
        assert gris_out = x"AA" and Cr_out = x"BB" and Cb_out = x"CC"
            report "Test 2 (mode couleur) en echec" severity error;

        -- Test 3 : Changement dynamique des signaux pendant sw1 = '1'
        gris <= x"11";
        Cr   <= x"22";
        Cb   <= x"33";
        wait for 20 ns;
        assert gris_out = x"11" and Cr_out = x"22" and Cb_out = x"33"
            report "Test 3 (suivi des entrees) en echec" severity error;

        -- Test 4 : Retour à sw1 = '0' avec changement du gris
        sw1  <= '0';
        gris <= x"FF";
        Cr   <= x"44";
        Cb   <= x"55";
        wait for 20 ns;
        assert gris_out = x"FF" and Cr_out = x"80" and Cb_out = x"80"
            report "Test 4 (retour mode gris) en echec" severity error;

        report "Simulation terminée." severity note;
        wait;
    end process;

end behavior;
