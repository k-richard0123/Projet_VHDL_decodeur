--------------------------------------------------------------------------------
-- Aide au debug sur la carte Nexys A7 : LED + afficheur 7 segments
--
--  LED0      : clignote 1 Hz                   -> le FPGA tourne
--  LED1      : periode mesuree dans la bande SSTV (1100..2400 Hz)
--  LED2      : 1200 Hz entendu (signal "sync" de detec_sync)
--  LED3      : synchro VALIDEE (sync_val), reste allumee 1 s
--  LED4      : des pixels sont ecrits en VRAM
--  LED8..15  : vu-metre du micro (crete de |pcm| sur 50 ms)
--              LED8 >= 128, LED9 >= 256, ... LED15 >= 16384
--              (le seuil d'hysteresis par defaut, 512, correspond a LED10)
--
--  7 segments, 4 chiffres de droite : periode T mesuree en us (rafraichie 4x/s)
--              1200 Hz -> 833   1500 Hz -> 666   1900 Hz -> 526   2300 Hz -> 434
--  7 segments, 3 chiffres de gauche : numero de la ligne en cours d'ecriture (0..239)
--
--  Les impulsions courtes (1 cycle) sont "etirees" pour etre visibles a l'oeil.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity debug_carte is
    port (
        clk      : in  std_logic;                       -- 100 MHz
        rst      : in  std_logic;
        tick_1us : in  std_logic;
        pcm      : in  std_logic_vector(15 downto 0);   -- signe
        T        : in  std_logic_vector(11 downto 0);   -- periode en us
        sync     : in  std_logic;
        sync_val : in  std_logic;
        pix_we   : in  std_logic;
        ligne    : in  std_logic_vector(7 downto 0);

        led      : out std_logic_vector(15 downto 0);
        seg      : out std_logic_vector(6 downto 0);    -- seg(0)=CA ... seg(6)=CG, actifs a '0'
        an       : out std_logic_vector(7 downto 0)     -- anodes, actives a '0'
    );
end debug_carte;

architecture rtl of debug_carte is

    -- etirement : nb de us pendant lesquels la LED reste allumee
    constant US_100MS : integer := 100000;
    constant US_1S    : integer := 1000000;

    signal cpt_hb                         : integer range 0 to 499999 := 0;
    signal hb                             : std_logic := '0';
    signal et_bande, et_sync, et_val, et_pix : integer range 0 to US_1S := 0;

    signal crete      : unsigned(14 downto 0) := (others => '0');
    signal crete_aff  : unsigned(14 downto 0) := (others => '0');
    signal cpt_crete  : integer range 0 to 49999 := 0;

    signal T_aff      : unsigned(11 downto 0) := (others => '0');
    signal cpt_aff    : integer range 0 to 249999 := 0;

    signal cpt_mux    : integer range 0 to 999 := 0;
    signal num_chif   : unsigned(2 downto 0) := (others => '0');

    signal bcd_T, bcd_y : unsigned(15 downto 0);

    -- binaire 12 bits -> 4 chiffres BCD (algorithme "double dabble")
    function bin2bcd(b : unsigned(11 downto 0)) return unsigned is
        variable r : unsigned(27 downto 0) := (others => '0');
    begin
        r(11 downto 0) := b;
        for i in 0 to 11 loop
            for d in 0 to 3 loop
                if r(15 + 4*d downto 12 + 4*d) > 4 then
                    r(15 + 4*d downto 12 + 4*d) := r(15 + 4*d downto 12 + 4*d) + 3;
                end if;
            end loop;
            r := shift_left(r, 1);
        end loop;
        return r(27 downto 12);
    end function;

    -- chiffre -> segments (actifs a '0'), ordre g f e d c b a ; 15 = eteint
    function segments(c : unsigned(3 downto 0)) return std_logic_vector is
    begin
        case to_integer(c) is
            when 0 => return "1000000";
            when 1 => return "1111001";
            when 2 => return "0100100";
            when 3 => return "0110000";
            when 4 => return "0011001";
            when 5 => return "0010010";
            when 6 => return "0000010";
            when 7 => return "1111000";
            when 8 => return "0000000";
            when 9 => return "0010000";
            when others => return "1111111";
        end case;
    end function;

    function etire(cpt : integer; evt : std_logic; duree : integer) return integer is
    begin
        if evt = '1' then return duree;
        elsif cpt > 0 then return cpt - 1;
        else return 0;
        end if;
    end function;

begin

    process(clk)
        variable a     : unsigned(14 downto 0);
        variable v_abs : signed(15 downto 0);
        variable bande : std_logic;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                et_bande <= 0; et_sync <= 0; et_val <= 0; et_pix <= 0;
                crete <= (others => '0'); crete_aff <= (others => '0');
            else
                -- evenements courts memorises jusqu'au prochain tick_1us
                if sync_val = '1' then et_val <= US_1S;     end if;
                if pix_we   = '1' then et_pix <= US_100MS;  end if;

                if tick_1us = '1' then
                    -- clignotant 1 Hz
                    if cpt_hb = 499999 then cpt_hb <= 0; hb <= not hb;
                    else cpt_hb <= cpt_hb + 1; end if;

                    -- bande SSTV : 1100..2400 Hz  <=>  T dans 416..910 us
                    if unsigned(T) >= 416 and unsigned(T) <= 910 then bande := '1'; else bande := '0'; end if;
                    et_bande <= etire(et_bande, bande, US_100MS);
                    et_sync  <= etire(et_sync,  sync,  US_100MS);
                    if sync_val = '0' and et_val > 0 then et_val <= et_val - 1; end if;
                    if pix_we   = '0' and et_pix > 0 then et_pix <= et_pix - 1; end if;

                    -- crete de |pcm| sur 50 ms
                    v_abs := abs(signed(pcm));            -- |pcm| <= 16384 : tient sur 15 bits
                    a     := unsigned(v_abs(14 downto 0));
                    if cpt_crete = 49999 then
                        cpt_crete <= 0;
                        crete_aff <= crete;
                        crete     <= a;
                    else
                        cpt_crete <= cpt_crete + 1;
                        if a > crete then crete <= a; end if;
                    end if;

                    -- valeur de T affichee 4 fois par seconde (lisible)
                    if cpt_aff = 249999 then cpt_aff <= 0; T_aff <= unsigned(T);
                    else cpt_aff <= cpt_aff + 1; end if;

                    -- multiplexage des 8 chiffres : 1 chiffre par ms
                    if cpt_mux = 999 then cpt_mux <= 0; num_chif <= num_chif + 1;
                    else cpt_mux <= cpt_mux + 1; end if;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- LED
    ----------------------------------------------------------------------------
    led(0) <= hb;
    led(1) <= '1' when et_bande > 0 else '0';
    led(2) <= '1' when et_sync  > 0 else '0';
    led(3) <= '1' when et_val   > 0 else '0';
    led(4) <= '1' when et_pix   > 0 else '0';
    led(7 downto 5) <= (others => '0');

    g_vu : for i in 0 to 7 generate
        led(8 + i) <= '1' when crete_aff >= to_unsigned(2 ** (7 + i), 15) else '0';
    end generate;

    ----------------------------------------------------------------------------
    -- 7 segments
    ----------------------------------------------------------------------------
    bcd_T <= bin2bcd(T_aff);
    bcd_y <= bin2bcd(resize(unsigned(ligne), 12));

    process(num_chif, bcd_T, bcd_y)
        variable c : unsigned(3 downto 0);
    begin
        an <= (others => '1');
        an(to_integer(num_chif)) <= '0';
        case to_integer(num_chif) is
            when 0 => c := bcd_T(3 downto 0);
            when 1 => c := bcd_T(7 downto 4);
            when 2 => c := bcd_T(11 downto 8);
            when 3 => c := bcd_T(15 downto 12);
            when 4 => c := "1111";                 -- eteint
            when 5 => c := bcd_y(3 downto 0);
            when 6 => c := bcd_y(7 downto 4);
            when others => c := bcd_y(11 downto 8);
        end case;
        seg <= segments(c);
    end process;

end rtl;
