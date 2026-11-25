/*
 * sstv_robot.c — Encodeur SSTV (Robot 8 N&B, Robot 36 N&B, Robot 36 couleur) vers .wav
 *
 * Prend une image de n'importe quelle dimension (JPG, PNG, BMP, GIF, TGA, PSD,
 * PPM/PGM... grâce à stb_image), la redimensionne à la résolution du mode
 * choisi, puis génère le signal audio SSTV (FM à phase continue) dans un
 * fichier WAV PCM 16 bits mono.
 *
 * Compilation (stb_image.h doit être dans le même dossier) :
 *   gcc -O2 -Wall -o sstv_robot sstv_robot.c -lm
 *
 * Récupérer stb_image.h (domaine public / MIT) :
 *   curl -O https://raw.githubusercontent.com/nothings/stb/master/stb_image.h
 *
 * Utilisation :
 *   ./sstv_robot [options] image_entree sortie.wav
 *
 * Options :
 *   -m MODE   r8bw  : Robot 8 N&B   (160x120,  ~8 s,  VIS 2)
 *             r36bw : Robot 36 N&B  (320x240, ~36 s,  VIS 14)
 *             r36   : Robot 36 couleur (320x240, 36 s, VIS 8)  [défaut]
 *   -f AJUST  fit     : image entière, bandes noires si besoin  [défaut]
 *             crop    : remplit tout le cadre, rogne ce qui dépasse
 *             stretch : étire/déforme pour remplir le cadre
 *   -r TAUX   fréquence d'échantillonnage en Hz (défaut 44100)
 *   -v VOL    amplitude 0.0–1.0 (défaut 0.8)
 *   -p FICH   enregistre aussi l'image redimensionnée en .ppm (aperçu)
 *   -h        aide
 *
 * Références de timing : J.L. Barber, "Proposal for SSTV Mode Specifications"
 * (Dayton 2000) et SSTV Handbook (Robot B&W 8 : sync 10 ms / ligne 56 ms ;
 * Robot B&W 36 : sync 12 ms / ligne 138 ms).
 */

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_HDR
#include "stb_image.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* ------------------------------------------------------------------------ */
/* Fréquences SSTV                                                          */
/* ------------------------------------------------------------------------ */
#define F_SYNC   1200.0
#define F_BLACK  1500.0
#define F_WHITE  2300.0
#define F_LEADER 1900.0
#define F_VIS1   1100.0   /* bit VIS = 1 */
#define F_VIS0   1300.0   /* bit VIS = 0 */

/* valeur 0..255 -> fréquence 1500..2300 Hz */
static double val2freq(double v)
{
    if (v < 0.0) v = 0.0;
    if (v > 255.0) v = 255.0;
    return F_BLACK + v * (F_WHITE - F_BLACK) / 255.0;
}

/* ------------------------------------------------------------------------ */
/* Écriture WAV + oscillateur à phase continue                              */
/* ------------------------------------------------------------------------ */
typedef struct {
    FILE    *f;
    uint32_t rate;
    double   amp;
    double   phase;     /* phase courante (radians) */
    double   t_target;  /* temps cible en échantillons (fractionnaire) */
    uint64_t n;         /* nombre d'échantillons écrits */
} Wav;

static void put_u16(FILE *f, uint16_t v) { fputc(v & 0xFF, f); fputc(v >> 8, f); }
static void put_u32(FILE *f, uint32_t v) { put_u16(f, v & 0xFFFF); put_u16(f, v >> 16); }

static void wav_header(Wav *w, uint32_t data_bytes)
{
    fwrite("RIFF", 1, 4, w->f);
    put_u32(w->f, 36 + data_bytes);
    fwrite("WAVE", 1, 4, w->f);
    fwrite("fmt ", 1, 4, w->f);
    put_u32(w->f, 16);            /* taille du bloc fmt */
    put_u16(w->f, 1);             /* PCM */
    put_u16(w->f, 1);             /* mono */
    put_u32(w->f, w->rate);
    put_u32(w->f, w->rate * 2);   /* octets / seconde */
    put_u16(w->f, 2);             /* alignement */
    put_u16(w->f, 16);            /* bits / échantillon */
    fwrite("data", 1, 4, w->f);
    put_u32(w->f, data_bytes);
}

static int wav_open(Wav *w, const char *path, uint32_t rate, double amp)
{
    memset(w, 0, sizeof *w);
    w->f = fopen(path, "wb");
    if (!w->f) return -1;
    w->rate = rate;
    w->amp  = amp;
    wav_header(w, 0);             /* tailles corrigées à la fermeture */
    return 0;
}

static int wav_close(Wav *w)
{
    uint64_t bytes = w->n * 2;
    if (bytes > 0xFFFFFFFFu - 36) bytes = 0xFFFFFFFFu - 36;
    fseek(w->f, 0, SEEK_SET);
    wav_header(w, (uint32_t)bytes);
    return fclose(w->f);
}

/* Émet une fréquence pendant 'ms' millisecondes.
 * Le temps est accumulé en virgule flottante : aucune dérive de timing
 * même si la durée d'un pixel n'est pas un nombre entier d'échantillons. */
static void tone(Wav *w, double freq, double ms)
{
    w->t_target += ms * (double)w->rate / 1000.0;
    uint64_t end = (uint64_t)llround(w->t_target);
    double dphi = 2.0 * M_PI * freq / (double)w->rate;

    while (w->n < end) {
        w->phase += dphi;
        if (w->phase > 2.0 * M_PI) w->phase -= 2.0 * M_PI;
        double s = w->amp * sin(w->phase) * 32767.0;
        int16_t v = (int16_t)lrint(s);
        put_u16(w->f, (uint16_t)v);
        w->n++;
    }
}

static void silence(Wav *w, double ms)
{
    w->t_target += ms * (double)w->rate / 1000.0;
    uint64_t end = (uint64_t)llround(w->t_target);
    while (w->n < end) { put_u16(w->f, 0); w->n++; }
    w->phase = 0.0;
}

/* En-tête de calibration + code VIS (7 bits LSB d'abord, parité paire) */
static void send_vis(Wav *w, int code)
{
    tone(w, F_LEADER, 300.0);
    tone(w, F_SYNC,    10.0);
    tone(w, F_LEADER, 300.0);
    tone(w, F_SYNC,    30.0);          /* bit de start */

    int ones = 0;
    for (int i = 0; i < 7; i++) {
        int b = (code >> i) & 1;
        ones += b;
        tone(w, b ? F_VIS1 : F_VIS0, 30.0);
    }
    tone(w, (ones & 1) ? F_VIS1 : F_VIS0, 30.0);   /* parité paire */
    tone(w, F_SYNC, 30.0);             /* bit de stop */
}

/* ------------------------------------------------------------------------ */
/* Redimensionnement (séparable : moyenne par zone en réduction,            */
/* bilinéaire en agrandissement)                                            */
/* ------------------------------------------------------------------------ */

/* Rééchantillonne un signal 1D : src[0..sn-1] (pas 'sstride'), sur la plage
 * source [r0, r0+rw) vers dst[0..dn-1] (pas 'dstride'). */
static void resample_1d(const float *src, int sn, int sstride, double r0, double rw,
                        float *dst, int dn, int dstride)
{
    double scale = rw / (double)dn;
    for (int i = 0; i < dn; i++) {
        double a = r0 + i * scale;
        double b = a + scale;
        double acc = 0.0;

        if (scale <= 1.0) {                       /* agrandissement : bilinéaire */
            double c = 0.5 * (a + b) - 0.5;
            if (c < 0) c = 0;
            if (c > sn - 1) c = sn - 1;
            int j0 = (int)floor(c);
            int j1 = j0 + 1 < sn ? j0 + 1 : sn - 1;
            double t = c - j0;
            acc = (1.0 - t) * src[j0 * sstride] + t * src[j1 * sstride];
        } else {                                  /* réduction : moyenne par zone */
            int j0 = (int)floor(a), j1 = (int)ceil(b);
            double wsum = 0.0;
            for (int j = j0; j < j1; j++) {
                double lo = a > j ? a : j;
                double hi = b < j + 1 ? b : j + 1;
                double wt = hi - lo;
                if (wt <= 0) continue;
                int jj = j < 0 ? 0 : (j >= sn ? sn - 1 : j);
                acc  += wt * src[jj * sstride];
                wsum += wt;
            }
            if (wsum > 0) acc /= wsum;
        }
        dst[i * dstride] = (float)acc;
    }
}

typedef enum { FIT_FIT, FIT_CROP, FIT_STRETCH } FitMode;

/* Produit une image RGB flottante W x H (valeurs 0..255) à partir de l'image
 * source sw x sh (RGB 8 bits), selon le mode d'ajustement. */
static float *prepare_image(const unsigned char *rgb, int sw, int sh,
                            int W, int H, FitMode fit)
{
    /* rectangle source utilisé */
    double rx = 0, ry = 0, rw = sw, rh = sh;
    /* rectangle destination rempli */
    int ox = 0, oy = 0, dw = W, dh = H;

    double src_ar = (double)sw / sh, dst_ar = (double)W / H;

    if (fit == FIT_FIT) {
        if (src_ar > dst_ar) { dw = W; dh = (int)lround(W / src_ar); }
        else                 { dh = H; dw = (int)lround(H * src_ar); }
        if (dw < 1) dw = 1;
        if (dh < 1) dh = 1;
        ox = (W - dw) / 2;
        oy = (H - dh) / 2;
    } else if (fit == FIT_CROP) {
        if (src_ar > dst_ar) { rw = sh * dst_ar; rx = (sw - rw) / 2.0; }
        else                 { rh = sw / dst_ar; ry = (sh - rh) / 2.0; }
    }

    float *out = calloc((size_t)W * H * 3, sizeof(float));   /* fond noir */
    float *srcf = malloc((size_t)sw * sh * 3 * sizeof(float));
    float *tmp  = malloc((size_t)dw * sh * 3 * sizeof(float));
    float *res  = malloc((size_t)dw * dh * 3 * sizeof(float));
    if (!out || !srcf || !tmp || !res) {
        fprintf(stderr, "Erreur : mémoire insuffisante\n");
        exit(1);
    }

    for (size_t i = 0; i < (size_t)sw * sh * 3; i++) srcf[i] = rgb[i];

    /* passe horizontale : sw -> dw, pour chaque ligne et chaque canal */
    for (int y = 0; y < sh; y++)
        for (int c = 0; c < 3; c++)
            resample_1d(srcf + (size_t)y * sw * 3 + c, sw, 3, rx, rw,
                        tmp + (size_t)y * dw * 3 + c, dw, 3);

    /* passe verticale : sh -> dh, pour chaque colonne et chaque canal */
    for (int x = 0; x < dw; x++)
        for (int c = 0; c < 3; c++)
            resample_1d(tmp + (size_t)x * 3 + c, sh, dw * 3, ry, rh,
                        res + (size_t)x * 3 + c, dh, dw * 3);

    for (int y = 0; y < dh; y++)
        memcpy(out + ((size_t)(y + oy) * W + ox) * 3,
               res + (size_t)y * dw * 3, (size_t)dw * 3 * sizeof(float));

    free(srcf); free(tmp); free(res);
    return out;
}

static void save_ppm(const char *path, const float *img, int W, int H)
{
    FILE *f = fopen(path, "wb");
    if (!f) { perror(path); return; }
    fprintf(f, "P6\n%d %d\n255\n", W, H);
    for (int i = 0; i < W * H * 3; i++) {
        float v = img[i];
        fputc(v < 0 ? 0 : v > 255 ? 255 : (int)lrintf(v), f);
    }
    fclose(f);
}

/* ------------------------------------------------------------------------ */
/* Conversions couleur                                                      */
/* ------------------------------------------------------------------------ */
#define PX(img, W, x, y) ((img) + ((size_t)(y) * (W) + (x)) * 3)

/* Luminance pleine échelle (modes N&B) */
static double luma_full(const float *p)
{
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2];
}

/* YCrCb ITU-R BT.601 (plage 16..235 / 16..240) utilisé par Robot 36 */
static double ycc_Y (double r, double g, double b) { return  16.0 + ( 65.738 * r + 129.057 * g +  25.064 * b) / 256.0; }
static double ycc_RY(double r, double g, double b) { return 128.0 + (112.439 * r -  94.154 * g -  18.285 * b) / 256.0; }
static double ycc_BY(double r, double g, double b) { return 128.0 + (-37.945 * r -  74.494 * g + 112.439 * b) / 256.0; }

/* ------------------------------------------------------------------------ */
/* Modes                                                                    */
/* ------------------------------------------------------------------------ */
typedef enum { MODE_R8BW, MODE_R36BW, MODE_R36 } ModeId;

typedef struct {
    ModeId      id;
    const char *name;
    const char *label;
    int         width, height, vis;
} Mode;

static const Mode MODES[] = {
    { MODE_R8BW,  "r8bw",  "Robot 8 N&B",      160, 120,  2 },
    { MODE_R36BW, "r36bw", "Robot 36 N&B",     320, 240, 14 },
    { MODE_R36,   "r36",   "Robot 36 couleur", 320, 240,  8 },
};

/* Robot N&B : sync puis une ligne de luminance */
static void encode_bw(Wav *w, const float *img, int W, int H,
                      double sync_ms, double scan_ms)
{
    double px_ms = scan_ms / W;
    for (int y = 0; y < H; y++) {
        tone(w, F_SYNC, sync_ms);
        for (int x = 0; x < W; x++)
            tone(w, val2freq(luma_full(PX(img, W, x, y))), px_ms);
    }
}

/* Robot 36 couleur : chaque ligne = Y (88 ms) + une chrominance (44 ms).
 * Lignes paires : R-Y (séparateur 1500 Hz), impaires : B-Y (séparateur 2300 Hz).
 * La chrominance est moyennée sur 2 lignes et 2 pixels (160 échantillons). */
static void encode_r36(Wav *w, const float *img, int W, int H)
{
    const double y_px  = 88.0 / W;
    const double c_px  = 44.0 / (W / 2);

    for (int y = 0; y < H; y++) {
        int ya = y & ~1, yb = ya + 1 < H ? ya + 1 : ya;   /* paire de lignes */
        int even = (y % 2) == 0;

        tone(w, F_SYNC,  9.0);
        tone(w, F_BLACK, 3.0);

        for (int x = 0; x < W; x++) {
            const float *p = PX(img, W, x, y);
            tone(w, val2freq(ycc_Y(p[0], p[1], p[2])), y_px);
        }

        tone(w, even ? F_BLACK : F_WHITE, 4.5);
        tone(w, F_LEADER, 1.5);

        for (int cx = 0; cx < W / 2; cx++) {
            double r = 0, g = 0, b = 0;
            int xs[2] = { 2 * cx, 2 * cx + 1 < W ? 2 * cx + 1 : 2 * cx };
            int ys[2] = { ya, yb };
            for (int i = 0; i < 2; i++)
                for (int j = 0; j < 2; j++) {
                    const float *p = PX(img, W, xs[i], ys[j]);
                    r += p[0]; g += p[1]; b += p[2];
                }
            r /= 4; g /= 4; b /= 4;
            double v = even ? ycc_RY(r, g, b) : ycc_BY(r, g, b);
            tone(w, val2freq(v), c_px);
        }
    }
}

/* ------------------------------------------------------------------------ */
/* main                                                                     */
/* ------------------------------------------------------------------------ */
static void usage(const char *prog)
{
    fprintf(stderr,
        "Usage : %s [options] image_entree sortie.wav\n"
        "  -m MODE   r8bw | r36bw | r36  (défaut : r36 = Robot 36 couleur)\n"
        "  -f AJUST  fit | crop | stretch (défaut : fit)\n"
        "  -r TAUX   fréquence d'échantillonnage (défaut : 44100)\n"
        "  -v VOL    amplitude 0.0-1.0 (défaut : 0.8)\n"
        "  -p FICH   enregistre l'image redimensionnée en .ppm\n"
        "Formats d'entrée : JPG, PNG, BMP, GIF, TGA, PSD, PNM...\n", prog);
}

int main(int argc, char **argv)
{
    const Mode *mode = &MODES[2];
    FitMode fit = FIT_FIT;
    long rate = 44100;
    double vol = 0.8;
    const char *preview = NULL, *in = NULL, *out = NULL;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (a[0] == '-' && a[1] && !a[2] && strchr("mfrvp", a[1])) {
            if (i + 1 >= argc) { usage(argv[0]); return 1; }
            const char *v = argv[++i];
            switch (a[1]) {
            case 'm': {
                mode = NULL;
                for (size_t k = 0; k < sizeof MODES / sizeof *MODES; k++)
                    if (!strcmp(v, MODES[k].name)) mode = &MODES[k];
                if (!mode) { fprintf(stderr, "Mode inconnu : %s\n", v); return 1; }
                break;
            }
            case 'f':
                if      (!strcmp(v, "fit"))     fit = FIT_FIT;
                else if (!strcmp(v, "crop"))    fit = FIT_CROP;
                else if (!strcmp(v, "stretch")) fit = FIT_STRETCH;
                else { fprintf(stderr, "Ajustement inconnu : %s\n", v); return 1; }
                break;
            case 'r': rate = strtol(v, NULL, 10); break;
            case 'v': vol = strtod(v, NULL); break;
            case 'p': preview = v; break;
            }
        } else if (!strcmp(a, "-h") || !strcmp(a, "--help")) {
            usage(argv[0]); return 0;
        } else if (!in)  in = a;
        else if (!out)   out = a;
        else { usage(argv[0]); return 1; }
    }
    if (!in || !out) { usage(argv[0]); return 1; }
    if (rate < 8000 || rate > 192000) { fprintf(stderr, "Taux invalide (8000-192000)\n"); return 1; }
    if (vol <= 0.0 || vol > 1.0)      { fprintf(stderr, "Volume invalide (0-1)\n"); return 1; }

    int sw, sh, ch;
    unsigned char *rgb = stbi_load(in, &sw, &sh, &ch, 3);
    if (!rgb) {
        fprintf(stderr, "Impossible de lire '%s' : %s\n", in, stbi_failure_reason());
        return 1;
    }

    int W = mode->width, H = mode->height;
    float *img = prepare_image(rgb, sw, sh, W, H, fit);
    stbi_image_free(rgb);

    if (preview) save_ppm(preview, img, W, H);

    Wav w;
    if (wav_open(&w, out, (uint32_t)rate, vol) != 0) { perror(out); free(img); return 1; }

    silence(&w, 500.0);
    send_vis(&w, mode->vis);

    switch (mode->id) {
    case MODE_R8BW:  encode_bw(&w, img, W, H, 10.0,  56.0); break;
    case MODE_R36BW: encode_bw(&w, img, W, H, 12.0, 138.0); break;
    case MODE_R36:   encode_r36(&w, img, W, H);             break;
    }

    tone(&w, F_SYNC, 9.0);   /* impulsion de fin pour terminer la dernière ligne */
    silence(&w, 500.0);

    double secs = (double)w.n / rate;
    if (wav_close(&w) != 0) { perror(out); free(img); return 1; }
    free(img);

    printf("%s : %dx%d -> %dx%d, VIS %d, %.2f s, %ld Hz -> %s\n",
           mode->label, sw, sh, W, H, mode->vis, secs, rate, out);
    return 0;
}
