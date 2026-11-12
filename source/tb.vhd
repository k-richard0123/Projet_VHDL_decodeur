library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_detec_sync is
-- L'entité d'un testbench est toujours vide
end tb_detec_sync;

architecture Behavioral of tb_detec_sync is

    -- Déclaration du composant à tester
    component detec_sync
        Port( 
            clk  : in std_logic;        
            raz  : in std_logic;        
            T    : in std_logic_vector(11 downto 0);      
            sync : out std_logic
        );
    end component;

    -- Signaux internes pour relier au DUT (Device Under Test)
    signal clk  : std_logic := '0';
    signal raz  : std_logic := '1';
    signal T    : std_logic_vector(11 downto 0) := (others => '0');
    signal sync : std_logic;

    -- Définition de la période d'horloge (ex: 1 MHz)
    constant CLK_PERIOD : time := 1 us;

begin

    -- Instanciation du composant
    uut: detec_sync Port map (
        clk  => clk,
        raz  => raz,
        T    => T,
        sync => sync
    );

    -- Génération de l'horloge
    clk_process :process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Processus de stimulus pour tester différentes valeurs de T
    stim_proc: process
    begin
        -- 1. Maintien du Reset au démarrage
        raz <= '1';
        T   <= std_logic_vector(to_unsigned(0, 12));
        wait for 10 * CLK_PERIOD;
        
        -- Relâchement du reset
        raz <= '0';
        wait for 5 * CLK_PERIOD;

        -- 2. Test d'une valeur en dessous de la plage (< 800)
        -- ex: 500 us (2000 Hz) -> sync doit rester à '0'
        T <= std_logic_vector(to_unsigned(500, 12));
        wait for 5 * CLK_PERIOD;

        -- 3. Test d'une valeur DANS la plage (800 <= T <= 870)
        -- ex: 833 us (~1200 Hz) -> sync doit passer à '1'
        T <= std_logic_vector(to_unsigned(833, 12));
        wait for 5 * CLK_PERIOD;

        -- 4. Test d'une valeur au dessus de la plage (> 870)
        -- ex: 1000 us (1000 Hz) -> sync doit repasser à '0'
        T <= std_logic_vector(to_unsigned(1000, 12));
        wait for 5 * CLK_PERIOD;
        
        -- 5. Test des valeurs limites
        T <= std_logic_vector(to_unsigned(800, 12));
        wait for 5 * CLK_PERIOD;
        
        T <= std_logic_vector(to_unsigned(870, 12));
        wait for 5 * CLK_PERIOD;

        -- Fin de simulation
        wait;
    end process;

end Behavioral;