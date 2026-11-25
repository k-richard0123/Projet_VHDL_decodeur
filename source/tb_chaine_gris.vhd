--------------------------------------------------------------------------------
-- Testbench de la chaine niveaux de gris (A METTRE DANS "Simulation Sources")
--
--   faux micro PDM -> PDC_sig16 -> perio_metre -> detec_sync -> luminance
--
-- Le faux micro emet une ligne Robot 36 dont la luminance est un DEGRADE :
-- pixel x -> gris attendu = x*255/319 (noir a gauche, blanc a droite).
-- Le signal audio sinusoidal est converti en PDM par un modulateur sigma-delta
-- d'ordre 1, comme le fait le vrai micro.
--
-- A chaque pixel decode, on compare au gris attendu. A la fin de la ligne on
-- affiche l'erreur moyenne. Duree a simuler : ~165 ms  (run 170 ms dans Vivado ;
-- comptez quelques minutes).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_chaine_gris is
end tb_chaine_gris;

architecture sim of tb_chaine_gris is

    constant PERIODE_CLK : time := 10 ns;
    constant DEBUT_LIGNE : real := 0.005;      -- 5 ms de 1500 Hz avant la 1re synchro
    constant AMPLITUDE   : real := 0.5;        -- amplitude du son (pleine echelle = 1)
    constant TROU_US     : integer := 500;

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal div_1us    : integer range 0 to 99 := 0;
    signal tick_1us   : std_logic := '0';

    signal data_pdm   : std_logic := '0';
    signal clk_mic    : std_logic;
    signal pcm        : std_logic_vector(15 downto 0);
    signal periode    : std_logic_vector(11 downto 0);
    signal sync_val   : std_logic;
    signal gris       : std_logic_vector(7 downto 0);
    signal x          : std_logic_vector(8 downto 0);
    signal pix_val    : std_logic;
    signal line_end   : std_logic;

    -- frequence emise a l'instant t (secondes)
    function freq(t_abs : real) return real is
        variable t  : real;
        variable px : integer;
    begin
        if t_abs < DEBUT_LIGNE then
            return 1500.0;                              -- avant la ligne
        end if;
        t := t_abs - DEBUT_LIGNE;
        if    t < 0.009 then return 1200.0;             -- synchro
        elsif t < 0.012 then return 1500.0;             -- palier
        elsif t < 0.100 then                            -- Y : degrade
            px := integer(floor((t - 0.012) / 275.0e-6));
            if px > 319 then px := 319; end if;
            return 1500.0 + 800.0 * real(px) / 319.0;
        elsif t < 0.1045 then return 1500.0;            -- separateur
        else  return 1900.0;                            -- palier + chroma neutre
        end if;
    end function;

begin

    clk <= not clk after PERIODE_CLK / 2;
    rst <= '1', '0' after 200 ns;

    p_tick : process(clk)
    begin
        if rising_edge(clk) then
            if div_1us = 99 then div_1us <= 0; tick_1us <= '1';
            else div_1us <= div_1us + 1; tick_1us <= '0'; end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Faux micro : sinusoide modulee en frequence -> PDM (sigma-delta ordre 1)
    -- La donnee change 50 ns apres le front montant de clk_mic.
    ----------------------------------------------------------------------------
    p_micro : process
        variable phase   : real := 0.0;
        variable v       : real := 0.0;
        variable echant  : real;
        variable t, t_pr : real := 0.0;
    begin
        wait until rising_edge(clk_mic);
        t := real(now / 1 ns) * 1.0e-9;
        phase := phase + MATH_2_PI * freq(t) * (t - t_pr);
        t_pr  := t;
        echant := AMPLITUDE * sin(phase);
        if v + echant > 0.0 then
            v := v + echant - 1.0;
            data_pdm <= '1' after 50 ns;
        else
            v := v + echant + 1.0;
            data_pdm <= '0' after 50 ns;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Chaine testee (meme cablage que toplvl.vhd)
    ----------------------------------------------------------------------------
    u_mic : entity work.PDC_sig16
        port map ( clk_100mhz => clk, reset => rst, data_pdm => data_pdm,
                   clk_mic => clk_mic, lr_sel => open,
                   pcm_data => pcm, sample_val => open );

    u_per : entity work.perio_metre
        generic map ( HYST => 512 )
        port map ( clk => clk, raz => rst, tick_1us => tick_1us,
                   sig_in => pcm, T => periode, T_val => open );

    u_sync : entity work.detec_sync
        generic map ( SYNC_MIN_US => 6000, TROU_US => TROU_US )
        port map ( clk => clk, raz => rst, tick_1us => tick_1us,
                   T => periode, sync => open, sync_val => sync_val );

    u_lum : entity work.luminance
        generic map ( CLK_MHZ => 100, PALIER_US => 3000 - TROU_US )
        port map ( clk => clk, raz => rst, sync_val => sync_val, T => periode,
                   data_out => gris, x_out => x, pix_val => pix_val,
                   line_end => line_end );

    ----------------------------------------------------------------------------
    -- Verification
    ----------------------------------------------------------------------------
    p_verif : process(clk)
        variable attendu  : integer;
        variable erreur   : integer;
        variable somme    : integer := 0;
        variable nb       : integer := 0;
    begin
        if rising_edge(clk) then
            if sync_val = '1' then
                report "Fin de synchro detectee a " & time'image(now) &
                       " (attendu ~" & real'image((DEBUT_LIGNE + 0.009) * 1000.0) &
                       " ms + ~0,7 ms de latence)";
            end if;

            if pix_val = '1' then
                attendu := (to_integer(unsigned(x)) * 255 + 159) / 319;
                erreur  := abs(to_integer(unsigned(gris)) - attendu);
                somme   := somme + erreur;
                nb      := nb + 1;
                if to_integer(unsigned(x)) mod 40 = 0 then
                    report "pixel " & integer'image(to_integer(unsigned(x))) &
                           " : gris = " & integer'image(to_integer(unsigned(gris))) &
                           " (attendu " & integer'image(attendu) & ")";
                end if;
            end if;

            if line_end = '1' then
                report "Fin de ligne : erreur moyenne = " &
                       integer'image(somme / nb) & " niveaux de gris sur " &
                       integer'image(nb) & " pixels";
                assert nb = 320 report "Nombre de pixels incorrect" severity error;
                assert somme / nb <= 10
                    report "Erreur moyenne trop grande" severity error;
                report "Simulation terminee" severity failure;   -- arrete la simu
            end if;
        end if;
    end process;

    -- garde-fou : si rien n'est decode
    p_timeout : process
    begin
        wait for 200 ms;
        report "TIMEOUT : aucune ligne decodee (synchro non detectee ?)" severity failure;
        wait;
    end process;

end sim;
