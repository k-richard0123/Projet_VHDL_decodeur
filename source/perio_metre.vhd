
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
           T        : out std_logic_vector(11 downto 0);   -- periode COMPLETE en us (somme des 2 dernieres 1/2 periodes)
           T_val    : out std_logic                        -- '1' un cycle quand T est mis a jour
    );
end perio_metre;

architecture Behavioral of perio_metre is

    signal   hyst_s  : signed(15 downto 0);
    constant CNT_MAX : unsigned(9 downto 0) := (others => '1');      -- 1023 us : saturation

    signal cnt       : unsigned(9 downto 0) := (others => '0');  -- nb de us comptes sur la 1/2 periode
    signal cnt_hys   : std_logic := '0';  -- '0' : on attend de passer sous -hyst, '1' : au-dessus de +hyst
    signal sig_audio : signed(15 downto 0) := (others => '0');

    -- Filtre passe-bas audio (2 filtres du 1er ordre en cascade, coupure ~2,5 kHz
    -- a 1 echantillon / us) : enleve le bruit qui fait "trembler" les passages
    -- par zero quand le son est faible.   lp = 64 x sortie du filtre
    signal lp1, lp2  : signed(23 downto 0) := (others => '0');

    signal demi_prec : unsigned(10 downto 0) := (others => '0');  -- 1/2 periode precedente (us)

begin

    hyst_s <= signed('0' & hyst);   -- toujours positif

process(clk)
        variable y1, y2 : signed(23 downto 0);
        variable demi   : unsigned(10 downto 0);
    begin
        if rising_edge(clk) then
            T_val <= '0';

            if raz = '1' then                --(Ré)Initialisations
                sig_audio <= (others => '0');
                T         <= (others => '0');
                T_val     <= '0';
                cnt       <= (others => '0');
                cnt_hys   <= '0';
                demi_prec <= (others => '0');

            elsif tick_1us = '1' then
                -- filtre passe-bas : lp <- lp + entree - lp/64 ; sortie = lp/64
                y1  := lp1 + resize(signed(sig_in), 24) - shift_right(lp1, 6);
                lp1 <= y1;
                y2  := lp2 + shift_right(y1, 6) - shift_right(lp2, 6);
                lp2 <= y2;
                sig_audio <= resize(shift_right(y2, 6), 16);   --on échantillonne le signal filtré toutes les 1 us

                demi := resize(cnt, 11) + 1;   -- le +1 compense le cycle de retard de sig_audio

                if cnt_hys = '0' then
                    if sig_audio >= -hyst_s then   -- toujours dans le bandeau
                        if cnt /= CNT_MAX then cnt <= cnt + 1; end if;   -- saturation (silence)
                    else                           -- on passe sous -hyst : fin de la 1/2 periode
                        -- T = 1/2 periode precedente + 1/2 periode actuelle :
                        -- une erreur sur l'instant d'un passage allonge une 1/2 periode
                        -- et raccourcit l'autre d'autant, la somme reste juste.
                        T         <= std_logic_vector(resize(demi_prec, 12) + demi);
                        T_val     <= '1';
                        demi_prec <= demi;
                        cnt_hys   <= '1';
                        cnt       <= (others => '0');
                    end if;

                else  -- cnt_hys = '1' : 2e 1/2 periode
                    if sig_audio <= hyst_s then
                        if cnt /= CNT_MAX then cnt <= cnt + 1; end if;
                    else
                        T         <= std_logic_vector(resize(demi_prec, 12) + demi);
                        T_val     <= '1';
                        demi_prec <= demi;
                        cnt_hys   <= '0';
                        cnt       <= (others => '0');
                    end if;
                end if;
            end if;
        end if;
end process;

end Behavioral;
