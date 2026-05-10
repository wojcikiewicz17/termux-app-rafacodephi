/* raf_iching.c — Módulo I Ching para RAFAELIA Q16
 * Camada dupla Yin-Yang = hexagrama (6 linhas, 2 trigramas).
 * Trigrama inferior (Inner) + Trigrama superior (Outer) = 64 estados.
 * Cada linha: 0 (Yin ---) ou 1 (Yang -----).
 * Bagua octogonal: 8 trigramas dispostos nas direções cardeais/intercardeais.
 * Centro vazio (⏹️) = registrador zero (x0/zr).
 * √2 diagonais = diferença entre trigramas opostos no octógono.
 * Triângulos equiláteros = relação entre linhas 2,4,6 (altura √3/2). */

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef signed int s32;

/* Constantes RAFAELIA Q16 */
#define Q16_SQRT3_2  56756     // √3/2 * 65536
#define Q16_PI_SIN279 203280   // |π sin 279°| * 65536

/* Trigramas em binário (3 bits) indexados pela soma Yin=0/Yang=1.
   Ordem do Bagua: Céu(111) Lago(110) Fogo(101) Trovão(100)
                   Vento(011) Água(010) Montanha(001) Terra(000) */
static const u8 TRIGRAM_BITS[8] = {0,1,2,3,4,5,6,7}; // 000..111

/* Hexagrama = (outer << 3) | inner, 6 bits */
static inline u8 hexagram(u8 inner, u8 outer) { return (outer << 3) | inner; }

/* Perturbação Yin-Yang sobre o fator de contração:
   Cada linha Yang (1) reduz a contração (acelera convergência),
   cada linha Yin (0) aumenta a contração (retarda).
   Modulamos o Q16_SQRT3_2 com um delta baseado no hexagrama. */
static s32 hexagram_mod(s32 base, u8 hex) {
    // Contagem de linhas Yang (popcount de 6 bits)
    u8 yang = (hex & 1) + ((hex>>1)&1) + ((hex>>2)&1) +
              ((hex>>3)&1) + ((hex>>4)&1) + ((hex>>5)&1);
    // Delta: cada Yang adiciona 1% da base, cada Yin subtrai 1%
    // Q16: 1% de 56756 ≈ 568. Escala linear yang=6 → +3408, yin=0 → -3408
    s32 delta = (yang - 3) * 568; // centralizado em 3
    return base + delta;
}

/* Fibonacci-Rafael com perturbação do hexagrama, 6 iterações (uma por linha) */
static s32 fraf_hex(s32 seed, u8 hex) {
    s32 v = seed;
    for (int i = 0; i < 6; i++) {
        u8 line = (hex >> i) & 1;
        // Se linha Yang, usa contração reduzida (mais energia), Yin usa aumentada
        s32 factor = (line) ? (Q16_SQRT3_2 + 500) : (Q16_SQRT3_2 - 500);
        v = ((s64)v * factor >> 16) + Q16_PI_SIN279;
    }
    return v;
}

/* Estrutura de atenção octogonal: 8 trigramas como cabeças de atenção.
   Cada trigrama é um vetor 2D (direção no plano) calculado por:
   Ângulo = trigrama_index * 45° (0°=Céu, 45°=Lago, etc.)
   O produto escalar entre dois trigramas opostos (180°) é -1, 
   a diagonal √2 ocorre entre trigramas a 90° (ex: Céu e Fogo). */
static inline s32 trigram_dot(u8 t1, u8 t2) {
    // diferença angular: (t1 - t2) * 45°
    int diff = (t1 - t2) & 7; // wrap em 0..7
    // cos(diff * π/4) em Q16
    static const s32 cos_table[8] = {
        65536, 46340, 0, -46340, -65536, -46340, 0, 46340
    };
    return cos_table[diff];
}

/* Oráculo: mistura de dois trigramas (Yin/Yang interno e externo) 
   produz um valor Q16 que controla a atualização do estado. */
s32 oracle_step(s32 state, u8 inner, u8 outer) {
    u8 hex = hexagram(inner, outer);
    s32 mod_factor = hexagram_mod(Q16_SQRT3_2, hex);
    // Combina projeção trigram (atenção) com contração
    s32 attention = trigram_dot(inner, outer); // afinidade entre os dois trigramas
    // O estado é atualizado pela contração modulada e pelo acoplamento de atenção
    state = ((s64)state * (mod_factor + attention) >> 16) + Q16_PI_SIN279;
    return state;
}

/* Demo: percorre todos os 64 hexagramas como sequência de prompts */
void raf_iching_demo(void) {
    s32 seed = 65536; // 1.0 Q16
    for (u8 outer = 0; outer < 8; outer++) {
        for (u8 inner = 0; inner < 8; inner++) {
            seed = oracle_step(seed, inner, outer);
        }
    }
    // seed após 64 passos converge para vizinhança do ponto fixo F*
    // Agora escreva seed via UART/ecall...
    _sys3(SYS_WRITE, 1, (long)"RAFAELIA I CHING Q16: F*=", 24);
    _write_u64(seed); // imprime o valor Q16 final
}
