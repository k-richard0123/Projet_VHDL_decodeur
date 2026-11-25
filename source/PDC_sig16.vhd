--------------------------------------------------------------------------------
-- Etage 0 : micro PDM -> echantillons PCM signes 16 bits
--
--  * Tout tourne sur l'horloge 100 MHz (un seul domaine d'horloge).
--    clk_mic (~2,38 MHz) est produit par un compteur et sort seulement vers
--    la broche du micro : il ne sert jamais d'horloge a l'interieur du FPGA.
--  * Le bit PDM est echantillonne juste avant le front montant de clk_mic
--    (lr_sel = '0' : donnee valide sur le front montant).
--  * Filtre : double moyenne glissante sur 64 bits PDM (CIC d'ordre 2 non
--    decime). La sortie est recalculee a chaque bit micro (2,38 MHz), ce qui
--    garde une bonne precision temporelle pour le periodemetre (1 us).
--      somme1 = nb de '1' sur les 64 derniers bits          : 0 .. 64
--      somme2 = somme des 64 dernieres valeurs de somme1    : 0 .. 4096
--      brut   = (somme2 - 2048) * 8                         : -16384 .. +16384
--      pcm    = brut - moyenne(brut)   (suppression du continu, passe-haut ~90 Hz)
--    Le signal sorti est donc toujours CENTRE SUR 0, meme si le micro a un decalage.
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity PDC_sig16 is
    generic (
        DEMI_PERIODE_MIC : integer := 21     -- 100 MHz / (2*21) = 2,38 MHz
    );
    Port (
        clk_100mhz : in  std_logic;                      -- horloge systeme 100 MHz
        reset      : in  std_logic;                      -- reset synchrone, actif a '1'
        data_pdm   : in  std_logic;                      -- donnees PDM du micro (asynchrone)
        front_ech  : in  std_logic;                      -- '0' : lecture juste avant le front MONTANT de clk_mic
                                                         -- '1' : lecture juste avant le front DESCENDANT (debug)
        clk_mic    : out std_logic;                      -- horloge vers le micro
        lr_sel     : out std_logic;                      -- selection canal (gauche)
        pcm_data   : out std_logic_vector(15 downto 0) := (others => '0');  -- echantillon PCM SIGNE (complement a 2)
        sample_val : out std_logic                       -- '1' pendant 1 cycle 100 MHz a chaque nouvel echantillon
    );
end PDC_sig16;

architecture Behavioral of PDC_sig16 is

    constant N_FILTRE : integer := 64;
    constant MILIEU   : integer := (N_FILTRE * N_FILTRE) / 2;   -- 2048

    signal compteur_div  : integer range 0 to DEMI_PERIODE_MIC - 1 := 0;
    signal clk_mic_r     : std_logic := '0';

    -- synchroniseur 2 bascules pour l'entree asynchrone
    signal pdm_s1, pdm_s2 : std_logic := '0';

    -- filtre (pas de reset : les registres a decalage restent coherents avec
    -- les sommes grace aux valeurs initiales, et Vivado peut les mettre en SRL)
    signal sr1    : std_logic_vector(N_FILTRE - 1 downto 0) := (others => '0');
    type sr2_t is array (0 to N_FILTRE - 1) of integer range 0 to N_FILTRE;
    signal sr2    : sr2_t := (others => 0);
    signal somme1 : integer range 0 to N_FILTRE := 0;
    signal somme2 : integer range 0 to N_FILTRE * N_FILTRE := 0;
    signal acc_dc : signed(31 downto 0) := (others => '0');   -- 4096 x moyenne du signal

begin

    clk_mic <= clk_mic_r;
    lr_sel  <= '0';

    p_mic : process(clk_100mhz)
        variable bit_in  : integer range 0 to 1;
        variable bit_old : integer range 0 to 1;
        variable s1_new  : integer range 0 to N_FILTRE;
        variable brut    : signed(31 downto 0);
        variable moy     : signed(31 downto 0);
        variable sortie  : signed(31 downto 0);
    begin
        if rising_edge(clk_100mhz) then
            pdm_s1 <= data_pdm;
            pdm_s2 <= pdm_s1;
            sample_val <= '0';

            if reset = '1' then
                compteur_div <= 0;
                clk_mic_r    <= '0';

            elsif compteur_div = DEMI_PERIODE_MIC - 1 then
                compteur_div <= 0;
                clk_mic_r    <= not clk_mic_r;

                if clk_mic_r = front_ech then    -- clk_mic va monter (ou descendre) : on lit le bit PDM
                    if pdm_s2 = '1' then bit_in := 1; else bit_in := 0; end if;
                    if sr1(N_FILTRE - 1) = '1' then bit_old := 1; else bit_old := 0; end if;

                    -- 1re moyenne glissante
                    sr1    <= sr1(N_FILTRE - 2 downto 0) & pdm_s2;
                    s1_new := somme1 + bit_in - bit_old;
                    somme1 <= s1_new;

                    -- 2e moyenne glissante
                    sr2(1 to N_FILTRE - 1) <= sr2(0 to N_FILTRE - 2);
                    sr2(0) <= s1_new;
                    somme2 <= somme2 + s1_new - sr2(N_FILTRE - 1);

                    -- Suppression de la composante continue (passe-haut ~90 Hz).
                    -- Le micro n'est jamais parfaitement a 50 % de '1' au repos : ce
                    -- decalage, s'il depasse le seuil d'hysteresis, empeche le
                    -- periodemetre de voir les passages par zero d'un son faible.
                    --   moyenne = acc_dc / 4096 ; sortie = brut - moyenne
                    -- (calcule avec somme2 du bit precedent : 1 bit de retard, sans importance)
                    brut   := to_signed((somme2 - MILIEU) * 8, 32);
                    moy    := shift_right(acc_dc, 12);
                    acc_dc <= acc_dc + brut - moy;
                    sortie := brut - moy;
                    if sortie > 32767 then
                        pcm_data <= std_logic_vector(to_signed(32767, 16));
                    elsif sortie < -32768 then
                        pcm_data <= std_logic_vector(to_signed(-32768, 16));
                    else
                        pcm_data <= std_logic_vector(sortie(15 downto 0));
                    end if;

                    sample_val <= '1';
                end if;
            else
                compteur_div <= compteur_div + 1;
            end if;
        end if;
    end process;

end Behavioral;
