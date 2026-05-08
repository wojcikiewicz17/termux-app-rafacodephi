// ======================================================================
// VECTRA 56‑CYCLE TOROIDAL DYNAMICS – FREESTANDING, NO LIBC, x87
// ======================================================================
// Comportamento: 
//   - Espaço de fase ≡ T³ (cada coordenada ∈ [0,1))
//   - Dinâmica determinística com 5 componentes + pesos adaptativos
//   - Sem divisão de inteiro longo, sem stack variável, sem runtime C
//   - Saída via syscall write
// Compilar: gcc -nostdlib -nostartfiles -ffreestanding -O2 -march=native -o vectra vectra.c
// ======================================================================
#define CYCLES  56
#define STEPS   200
#define DIM     3
#define ETA     0.01
#define EPS     1e-6

// --------------------- DADOS GLOBAIS ---------------------
double x[DIM], prev[DIM], prev2[DIM];
double new_x[DIM];
double phase, delta, C, H;
double W[5] = {0.2, 0.2, 0.2, 0.2, 0.2};
char outbuf[256];
int  outpos;

static const long long pow10[5] = {10000, 1000, 100, 10, 1};

// --------------------- ESCRITA ---------------------
void write_stdout(const char *s, int len) {
    __asm__ volatile (
        "mov $1, %%rax\n"
        "mov $1, %%rdi\n"
        "mov %0, %%rsi\n"
        "mov %1, %%rdx\n"
        "syscall"
        :
        : "r"(s), "r"(len)
        : "rax","rdi","rsi","rdx","rcx","r11"
    );
}

// --------------------- CONVERSOR DOUBLE -> STRING ---------------------
// Converte 'v' em string decimal com 5 casas, sem divisão de inteiros longos.
// Usa laço de subtração para extrair parte inteira.
void append_double(double v) {
    if (v < 0.0) { outbuf[outpos++] = '-'; v = -v; }
    // Arredonda para 5 casas decimais
    long long int_part = (long long)v;
    double frac = v - (double)int_part;
    long long frac_scaled = (long long)(frac * 100000.0 + 0.5);
    if (frac_scaled >= 100000) { int_part++; frac_scaled -= 100000; }

    // Parte inteira (subtração repetida sobre potências de 10^4..10^0)
    int started = 0;
    for (int p=4; p>=0; p--) {
        int digit = 0;
        long long sub = 1;
        for (int k=0; k<p; k++) sub *= 10;   // 10^p (até 10000)
        while (int_part >= sub) { int_part -= sub; digit++; }
        if (digit || started || p==0) {
            outbuf[outpos++] = '0' + digit;
            started = 1;
        }
    }

    outbuf[outpos++] = '.';

    // 5 dígitos decimais (extraídos do mesmo jeito, usando pow10)
    for (int i=0; i<5; i++) {
        long long divisor = pow10[i];
        int digit = 0;
        while (frac_scaled >= divisor) { frac_scaled -= divisor; digit++; }
        outbuf[outpos++] = '0' + digit;
    }
}

// --------------------- REDUÇÃO AO TORO ---------------------
static inline void to_torus(double *v) {
    // reduz v para [0,1) sem usar fmod/floor
    while (*v >= 1.0) *v -= 1.0;
    while (*v <  0.0) *v += 1.0;
}

// --------------------- PONTO DE ENTRADA _start ---------------------
void _start() {
    // Inicialização
    for (int i=0;i<DIM;i++) {
        x[i] = 0.1 * (i+1);          // já no intervalo [0,0.3)
        prev[i] = 0.0;
        prev2[i] = 0.0;
    }
    phase = 0.0;
    delta = 0.0;
    C = 0.5;
    H = 0.5;
    int cycle_counter = 0;

    const char header[] = "t, x0, x1, x2, delta, C, H, phase\n";
    write_stdout(header, sizeof(header)-1);

    for (int t=0; t<STEPS; t++) {
        double D[DIM], A[DIM], R[DIM], inv[DIM];

        // 1. Derivada
        for (int i=0;i<DIM;i++) D[i] = x[i] - prev[i];

        // 2. Antiderivada
        for (int i=0;i<DIM;i++) A[i] = x[i] + prev[i] + prev2[i];

        // 3. Recursão (seno via x87)
        for (int i=0;i<DIM;i++) {
            double arg = prev[i] + prev2[i] + phase;
            double res;
            __asm__ ("fldl %1 ; fsin ; fstpl %0" : "=m"(res):"m"(arg));
            R[i] = res;
        }

        // 4. Inversão estabilizada: I(x) = x/(ε + x²)
        for (int i=0;i<DIM;i++) {
            inv[i] = x[i] / (EPS + x[i]*x[i]);
        }

        // 5. Novo estado
        for (int i=0;i<DIM;i++) {
            new_x[i] = W[0]*D[i] + W[1]*A[i] + W[2]*R[i] + W[3]*inv[i] + W[4]*delta;
        }

        // Shift histórico
        for (int i=0;i<DIM;i++) {
            prev2[i] = prev[i];
            prev[i]  = x[i];
            x[i]     = new_x[i];
            // compactificação no toro
            to_torus(&x[i]);
        }

        // 6. Fase (0..CYCLES-1)
        cycle_counter = (cycle_counter + 1) % CYCLES;
        phase = (double)cycle_counter;

        // 7. Delta = sqrt(D⋅D)
        double sum_sq = D[0]*D[0] + D[1]*D[1] + D[2]*D[2];
        __asm__ ("fldl %1 ; fsqrt ; fstpl %0" : "=m"(delta):"m"(sum_sq));

        // 8. C = 1/(1+delta)
        C = 1.0 / (1.0 + delta);

        // 9. H = ln(1+delta)  (via log2, fyl2x)
        {
            double arg = 1.0 + delta;
            double log2;
            const double ln2 = 0.6931471805599453;
            __asm__ (
                "fld1\n"          // st(1)=1.0
                "fldl %1\n"       // st(0)=arg
                "fyl2x\n"         // st(0)=1*log2(arg)
                "fstpl %0"
                : "=m"(log2):"m"(arg)
            );
            H = log2 * ln2;
        }

        // 10. Atualização de pesos adaptativos
        if (delta > 1.0) { W[1] += ETA; W[3] += ETA; }
        else             { W[0] += ETA; }
        double sumW = W[0]+W[1]+W[2]+W[3]+W[4];
        for (int i=0;i<5;i++) W[i] /= sumW;

        // 11. Impressão
        outpos = 0;
        append_double((double)t);     outbuf[outpos++]=','; outbuf[outpos++]=' ';
        append_double(x[0]);          outbuf[outpos++]=','; outbuf[outpos++]=' ';
        append_double(x[1]);          outbuf[outpos++]=','; outbuf[outpos++]=' ';
        append_double(x[2]);          outbuf[outpos++]=','; outbuf[outpos++]=' ';
        append_double(delta);         outbuf[outpos++]=','; outbuf[outpos++]=' ';
        append_double(C);             outbuf[outpos++]=','; outbuf[outpos++]=' ';
        append_double(H);             outbuf[outpos++]=','; outbuf[outpos++]=' ';
        append_double(phase);
        outbuf[outpos++] = '\n';
        write_stdout(outbuf, outpos);
    }

    // Saída limpa
    __asm__ ("mov $60, %rax; xor %rdi, %rdi; syscall");
}
