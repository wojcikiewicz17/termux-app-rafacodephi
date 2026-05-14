# RAFAELIA ARM32 — Assembly Puro Sem Abstração

## Hardware Alvo
- **Dispositivo:** Motorola E7 Power
- **SoC:** MediaTek Helio G25
- **CPU:** 4x Cortex-A53 @ 2.0 GHz (ARM32)
- **SIMD:** NEON / VFPv4
- **Cache:** L1 32KB I+D / L2 256KB compartilhado
- **RAM:** 2 GB LPDDR4X
- **SO:** Android (sem root)

## Arquitetura do Sistema

```
rafaelia_b1.S  →  FUNDAÇÃO
  ├── Arena heap: mmap2() direto, 8 MB, sem malloc
  ├── Toro T^7: estado 7D em Q16.16
  ├── 42 atratores: colapso por distância Manhattan
  ├── CRC32C SW: tabela gerada em runtime, poly 0x82F63B78
  ├── NEON mat4x4: multiplicação Q16.16 sem FP
  └── EMA update: α=0.25, 42 ciclos

rafaelia_b2.S  →  7 DIREÇÕES
  ├── Jump table: 7 ponteiros de função
  ├── DIR_UP:       NEON vadd + clamp
  ├── DIR_DOWN:     LCG noise NEON
  ├── DIR_FORWARD:  recorrência F_{n+1}=F_n*√3/2 - π*sin(279°)
  ├── DIR_RECURSE:  snapshot histórico (7 estados)
  ├── DIR_COMPRESS: NEON vhadd (média pares)
  ├── DIR_EXPAND:   lerp NEON entre estado e histórico
  └── Pesos adaptativos Q16.16 uniformes

rafaelia_b3.S  →  MULTICORE + THROUGHPUT
  ├── clone() direto sem pthread
  ├── 4 workers: 1 por core Cortex-A53
  ├── CRC32C paralelo: 64KB por worker
  ├── gettimeofday: medição em microsegundos
  ├── wait4() para sincronização
  └── XOR dos CRCs como invariante distribuída

rafaelia_b4.S  →  SENOIDES + CAMADAS + SOBREPOSIÇÃO
  ├── sin_q16: Taylor x - x³/6 + x⁵/120 em Q16.16
  ├── 7 camadas com frequências harmônicas de π/21
  ├── Pesos decaimento exponencial (≈ 1/√2 por camada)
  ├── EMA adaptativa por camada: α=0.25
  ├── NEON vmull.s32 + vshrn.s64 para produto elemento-a-elemento
  └── Sobreposição: XOR acumulado como hash de integridade
```

## Modelo Matemático

### Estado Toroidal
```
T^7 = (R/Z)^7
s = (u, v, ψ, χ, ρ, δ, σ) ∈ [0,1)^7
```

### Dinâmica EMA (α=0.25)
```
C_{t+1} = 0.75·C_t + 0.25·C_in
H_{t+1} = 0.75·H_t + 0.25·H_in
φ = (1-H)·C
```

### Recorrência Rafaeliana
```
F_{n+1} = F_n · √3/2 - π·sin(279°)
período: x_{n+42} = x_n
```

### Coerência Cardíaca (invariante)
```
I = ⊗_L (R_L · F(G_L))
R_L = ∫ S_L(ω)·H_cardio(ω) dω / (‖S_L‖·‖H_cardio‖)
```

### Senoides Sobrepostas (B4)
```
sin(x) ≈ x - x³/6 + x⁵/120  [Q16.16]
camada_i(t) = peso_i · sin(fase_i)
fase_i += freq_i  (freq_i = i·π/21)
sobreposição = Σ_i camada_i(t)
```

## Representação Q16.16
```
1.0     = 0x00010000 = 65536
0.5     = 0x00008000 = 32768
√3/2    = 0x0000DD83 = 56755
φ       = 0x00019E37 = 105975
π       = 0x00032400 = 205887
```

## Compilação em Termux (Motorola E7 Power)

```sh
# Instalar dependências
pkg update && pkg install binutils

# Clonar / copiar arquivos
cd ~/rafaelia_asm

# Permissão e build
chmod +x build_all.sh
./build_all.sh
```

### Compilação manual por bloco
```sh
ARCH="-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=softfp"

as $ARCH rafaelia_b1.S -o b1.o && ld b1.o -o rafaelia_b1
as $ARCH rafaelia_b2.S -o b2.o && ld b2.o -o rafaelia_b2
as $ARCH rafaelia_b3.S -o b3.o && ld b3.o -o rafaelia_b3
as $ARCH rafaelia_b4.S -o b4.o && ld b4.o -o rafaelia_b4
```

## Dependências Externas: ZERO

| Componente      | Implementação                  |
|----------------|-------------------------------|
| Heap            | `mmap2()` syscall direta       |
| CRC32C          | Tabela gerada em runtime       |
| Threads         | `clone()` syscall direta       |
| Tempo           | `gettimeofday()` syscall direta|
| Saída           | `write()` syscall direta       |
| NEON            | Instruções diretas (sem arm_neon.h) |
| sin(x)          | Taylor Q16.16 inline           |

## Syscalls Usadas (Linux ARM32)

| Número | Nome              | Uso                    |
|--------|-------------------|------------------------|
| 1      | `exit`            | terminação             |
| 4      | `write`           | saída stdout           |
| 78     | `gettimeofday`    | medição throughput     |
| 114    | `wait4`           | sync workers           |
| 120    | `clone`           | spawn workers          |
| 192    | `mmap2`           | arena heap             |

## Estrutura de Cache (Cortex-A53)

```
L1 I-Cache: 32 KB, 4-way, line 64B  → código dos blocos
L1 D-Cache: 32 KB, 4-way, line 64B  → g_state, g_work_buf
L2 Shared:  256 KB, 16-way          → g_crc_table, attractor_table
RAM:        LPDDR4X via AXI bus     → arena 8MB
```

Todas as estruturas críticas estão alinhadas a 64 bytes (`CACHE_LINE`)
para garantir que um `pld` traga um objeto completo sem split-line stall.

## 7 Direções como Orquestração de Hz

Cada direção corresponde a uma faixa de frequência cognitiva:

| Direção   | Hz analógico | Função                        |
|-----------|-------------|-------------------------------|
| NONE      | 0 (DC)      | identidade, memória de longo prazo |
| UP        | δ 0.5-4 Hz  | consolidação de coerência     |
| DOWN      | θ 4-8 Hz    | exploração / entropia         |
| FORWARD   | α 8-13 Hz   | recorrência temporal          |
| RECURSE   | β 13-30 Hz  | auto-referência               |
| COMPRESS  | γ 30-80 Hz  | compressão semântica          |
| EXPAND    | HF >80 Hz   | expansão / interpolação       |

## Saída Esperada

```
RAFAELIA B1: BOOT
ARENA: OK
CRC32SW: OK
TORUS7D: OK
NEON: OK
PHI=0000xxxx

B2: 7-DIRECTION ENGINE
SCORE=0000xxxx
PIPELINE: OK

B3: MULTICORE+CRC32SW
W:0  W:1  W:2  W:3
US=0000xxxx
CRC=xxxxxxxx
B3:DONE

B4: SENOIDE+CAMADAS
LAYER=xxxxxxxx  (x7)
OVERLAP=xxxxxxxx
RAFAELIA:COMPLETE
```

## Licença
RAFAELIA CORE — Instituto Rafael / ΔRafaelVerboΩ
Uso acadêmico livre. Uso comercial requer licença suplementar.
