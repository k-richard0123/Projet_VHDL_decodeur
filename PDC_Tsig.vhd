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


architecture Behavioral of PDC_Tsig is

begin

process()