
------------------------------------------------------------------------------
-- Etage 1 : periodemetre
--
--les conditions du période-metre sont:
--signal centré sur 0 (fourni par PDC_sig16, environ -16384 .. +16384)
--gamme de fréquence entre 1200 et 2300 Hz
--
-- Horloge 100 MHz + "tick_1us" ('1' un cycle sur 100) : le compteur avance de
-- 1 a chaque microseconde, donc T sort directement en microsecondes.
-- (Avant : horloge 1 MHz fabriquee par de la logique -> 2e domaine d'horloge.)
--
--L'ensemble de l'explication sur les 1/2 T, bandeaux,... peut sembler compliquer mais ce n'est qu'un principe d'hysteresis
--qui se comprend tres facilement avec un dessin tel que celui ci
--
--                   #####                                    .---.
--                ###     ###                                /     \
--              ##           ##                             /       \
-- +hyst ------#---------------#---------------------------*---------\------- (Seuil haut)
--            /                 #                         *           \
--           /                   #                       *             \
--     0 ---/---------------------#---------------------*---------------\---- (Axe 0)
--                                 #                   *
--                                  #                 *
-- -hyst ----------------------------#---------------*----------------------- (Seuil bas)
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
    Port ( clk      : in  std_logic;                       -- 100 MHz
           hyst     : in  std_logic_vector(14 downto 0);   -- demi-largeur de la bande d'hysteresis (unites PCM, > 0)
           raz      : in  std_logic;                       -- reset synchrone, actif a '1'
           tick_1us : in  std_logic;                       -- '1' un cycle toutes les 1 us
           sig_in   : in  std_logic_vector(15 downto 0);   -- signal audio SIGNE centre sur 0
           T        : out std_logic_vector(11 downto 0);   -- periode en us (toujours paire)
           T_val    : out std_logic                        -- '1' un cycle quand T est mis a jour
    );
end perio_metre;

architecture Behavioral of perio_metre is

    signal   hyst_s  : signed(15 downto 0);
    constant CNT_MAX : unsigned(9 downto 0) := (others => '1');      -- 1023 us : saturation

    signal cnt       : unsigned(9 downto 0) := (others => '0');  -- nb de us comptes sur la 1/2 periode
    signal cnt_hys   : std_logic := '0';  -- '0' : on attend de passer sous -hyst, '1' : au-dessus de +hyst
    signal sig_audio : signed(15 downto 0) := (others => '0');

begin

    hyst_s <= signed('0' & hyst);   -- toujours positif

process(clk)
    begin
        if rising_edge(clk) then
            T_val <= '0';

            if raz = '1' then                --(Ré)Initialisations
                sig_audio <= (others => '0');
                T         <= (others => '0');
                T_val     <= '0';
                cnt       <= (others => '0');
                cnt_hys   <= '0';

            elsif tick_1us = '1' then
                sig_audio <= signed(sig_in);     --on échantillonne le signal audio toutes les 1 us

                if cnt_hys = '0' then
                    if sig_audio >= -hyst_s then   -- toujours dans le bandeau
                        if cnt /= CNT_MAX then cnt <= cnt + 1; end if;   -- saturation (silence)
                    else                           -- on passe sous -hyst : fin de la 1/2 periode
                        -- T = 2 * (cnt+1) us ; le +1 compense le cycle de retard de sig_audio
                        T       <= std_logic_vector(shift_left(resize(cnt, 12) + 1, 1));
                        T_val   <= '1';
                        cnt_hys <= '1';
                        cnt     <= (others => '0');
                    end if;

                else  -- cnt_hys = '1' : 2e 1/2 periode
                    if sig_audio <= hyst_s then
                        if cnt /= CNT_MAX then cnt <= cnt + 1; end if;
                    else
                        T       <= std_logic_vector(shift_left(resize(cnt, 12) + 1, 1));
                        T_val   <= '1';
                        cnt_hys <= '0';
                        cnt     <= (others => '0');
                    end if;
                end if;
            end if;
        end if;
end process;

end Behavioral;
