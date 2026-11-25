--------------------------------------------------------------------------------
-- Etage 2a : detection de la synchro ligne (1200 Hz pendant 9 ms)
--
--  * sync     : '1' tant que la periode mesuree est dans la plage des 1200 Hz
--               (833 us, tolerance T_MIN .. T_MAX)
--  * sync_val : impulsion d'UN cycle 100 MHz a la FIN d'une synchro qui a dure
--               au moins SYNC_MIN_US. C'est ce front qui cale le debut de ligne.
--
--  Une mesure ratee au milieu de la synchro (bruit) ne casse pas la detection :
--  on ne declare la fin de la synchro qu'apres TROU_US us passes hors plage.
--  Consequence : sync_val arrive TROU_US apres la vraie fin de la synchro, ce qui
--  est compense dans "luminance" (palier raccourci de TROU_US).
--
--  Correction principale par rapport a l'ancienne version : le "else" qui remettait
--  le compteur a 0 a chaque cycle (donc sync_val ne passait jamais a '1'), et
--  l'unite du seuil (900000 coups a 1 MHz = 0,9 s, au lieu de 9 ms).
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity detec_sync is
    generic (
        T_MIN       : integer := 790;    -- us  (1266 Hz)
        T_MAX       : integer := 880;    -- us  (1136 Hz)
        SYNC_MIN_US : integer := 6000;   -- duree mini de 1200 Hz pour valider une synchro (9 ms nominal)
        TROU_US     : integer := 500     -- duree hors plage avant de declarer la fin de synchro
    );
    Port ( clk      : in  std_logic;                       -- 100 MHz
           raz      : in  std_logic;                       -- reset synchrone, actif a '1'
           tick_1us : in  std_logic;
           T        : in  std_logic_vector(11 downto 0);   -- periode en us
           sync     : out std_logic;
           sync_val : out std_logic
    );
end detec_sync;

architecture Behavioral of detec_sync is

    signal sig_sync : std_logic := '0';
    signal cnt      : integer range 0 to 16383 := 0;        -- us passes a 1200 Hz
    signal trou     : integer range 0 to TROU_US := 0;      -- us passes hors plage

begin

    sync <= sig_sync;

    process(clk)
    begin
        if rising_edge(clk) then
            sync_val <= '0';

            if raz = '1' then
                sig_sync <= '0';
                cnt      <= 0;
                trou     <= 0;

            else
                -- plage des 1200 Hz
                if unsigned(T) >= T_MIN and unsigned(T) <= T_MAX then
                    sig_sync <= '1';
                else
                    sig_sync <= '0';
                end if;

                if tick_1us = '1' then
                    if sig_sync = '1' then
                        if cnt < 16383 then cnt <= cnt + 1; end if;
                        trou <= 0;
                    elsif cnt > 0 then                    -- on etait en synchro, on en sort peut-etre
                        if trou = TROU_US - 1 then        -- vraiment sorti
                            if cnt >= SYNC_MIN_US then
                                sync_val <= '1';          -- debut du palier 1500 Hz
                            end if;
                            cnt  <= 0;
                            trou <= 0;
                        else
                            trou <= trou + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;
