# ARMÉ — Documentação Técnica de Algoritmos, Lógica e Design

## Objetivo
Documentar, de forma profissional, os algoritmos, a lógica estrutural e o conteúdo de design presentes nos arquivos do diretório `Arme/`.

---

## 1) Mapa de arquivos e papel técnico

| Arquivo | Papel | Classe |
|---|---|---|
| `RAFAELIA_MASTER.txt` | Script monolítico de bootstrap/build/runtime multi-arquitetura | Orquestração de toolchain |
| `Compilador ASM.sh` | Especificação/script de compilador de estados `.raf` para C+ASM | Compilador/transpilador |
| `4.md` | Blocos geradores de código para RISC-V32/macOS e notas low-level | Geração de módulo |
| `5.md` | Modelo I Ching em Q16 com dinâmica de estado e atenção trigramática | Algoritmo matemático |
| `7.md` | Sistema TTL8 (8 estados em bitmap), contratos de erro e despacho O(1) | Máquina de estados |
| `Conceito.txt` | Fundamentos de bare-metal em microcontroladores e registradores | Arquitetura de hardware |
| `Pomeg.txt` | Texto conceitual/fundacional | Base conceitual |
| `RAFAELIA_SEMENTES (1) (1).txt` | Caderno de sementes matemáticas e hipóteses formais | Pesquisa/formulação |
| `README_PROFISSIONAL.md` | Plano de refatoração e governança técnica | Governança |

---

## 2) Algoritmos e contratos por arquivo

## 2.1 `RAFAELIA_MASTER.txt`

### Lógica principal
- Executável em bash que centraliza: detecção de ambiente, seleção de arquitetura, geração/compilação/execução de artefatos.
- Implementa caminho de operação por flags (`--arm64`, `--arm32`, `--riscv32`, `--mac`, etc.).
- Contém modo de ambiente Android/Termux com ajustes de compatibilidade (PIE, bionic, páginas grandes).

### Contratos implícitos
- Entrada: argumentos CLI opcionais.
- Saída: binários/artigos intermediários e logs de build.
- Invariantes:
  - `set -euo pipefail` habilitado;
  - ferramenta de compilação detectada em runtime;
  - fallback condicionado por arquitetura.

### Pontos de design
- Monólito auto-hospedado (doc+build+execução em um único artefato).
- Forte ênfase em portabilidade de baixo nível e cross-compile.

---

## 2.2 `Compilador ASM.sh`

### Pipeline do compilador RSC
1. Pré-processamento (`#FLAG`, `#SHADOW`, macros).
2. Lexer (tokenização de `.raf`).
3. Parser (AST de estados).
4. Otimizações (merge de flags, eliminação de estado morto, marcação tail-call).
5. Codegen (C + inline ASM por alvo).
6. Síntese final de `.c/.h` e constantes.

### DSL `.raf` descrita
- Diretivas de estado: `#STATE{...}`.
- Blocos de ASM por plataforma: `#ASM[ARM64|ARM32|X64|GENERIC]`.
- Controle de fluxo declarado no source da DSL.
- Recursos de instrumentação: `#HEX`, `#TAIL`, `#SHADOW`.

### Lógica de runtime do compilador
- Bateria de geração por etapas com logging.
- Modelagem de tipos próprios (`u8/u16/u32/...`) e arena allocator.

---

## 2.3 `4.md`

### Conteúdo algorítmico relevante
- Bloco gerador de módulo RISC-V32 (`raf_rv32.c`) com:
  - syscalls via `ecall` (`a7` número, `a0-a5` argumentos);
  - leitura de CSR (`rdcycle`, `rdtime`, `mhartid`);
  - função de contração discreta `fraf_q8` em Q8.

### Fórmula central (Q8)
`v_{n+1} = ((v_n * 222) >> 8) + 49`
- 222 ≈ `(sqrt(3)/2) * 256`
- 49 ≈ termo de excitação constante
- saturação explícita em `[0,255]`

### Contratos de hardware
- Escrita UART por mapeamento de memória (`USART1_SR`, `USART1_DR`).
- `_start` como ponto de entrada freestanding.

---

## 2.4 `5.md`

### Núcleo matemático
- Representação de hexagramas (`inner`, `outer`) em 6 bits.
- Modulação do fator de contração por contagem de linhas Yang (popcount).
- Atualização de estado em Q16 com termo trigonométrico e acoplamento de atenção.

### Componentes
- `hexagram(inner, outer)` → codifica estado 6 bits.
- `hexagram_mod(base, hex)` → ajusta contração por polaridade Yin/Yang.
- `trigram_dot(t1, t2)` → afinidade angular via tabela de cosseno em Q16.
- `oracle_step(state, inner, outer)` → passo dinâmico global.

### Equação efetiva
`state' = ((state * (mod_factor + attention)) >> 16) + Q16_PI_SIN279`

### Observação de implementação
- O arquivo possui referência a `s64` sem typedef explícito local: pendência para normalização de tipos.

---

## 2.5 `7.md`

### Máquina de estados TTL8
- Modelo de 8 estados em bitmap (ALLOW, DENY, RETRY, FAULT, TIMEOUT, OVERFLOW, CORRUPT, PANIC/VOID).
- Permite superposição de estados via OR bit a bit.
- Regras de classificação derivadas por máscaras (`recoverable`, `terminal`, etc.).

### Estruturas de design
- `RafTTL8`: snapshot com status, histórico, tentativas, erro, checkpoints e tempo.
- Tabela de despacho potencial `lookup[256]` para resolução O(1) por bitmap.

### Contratos
- Estado é sempre um `u8` bitmask;
- combinações são válidas e representam estados compostos;
- códigos de erro hex com nibbles semânticos.

---

## 2.6 `Conceito.txt`

### Conteúdo técnico
- Mapeamento direto de registradores AVR (ATmega328P), GPIO e timers.
- Demonstração de operações de bit sem HAL:
  - write/read/toggle por endereço fixo;
  - discussão de custo de ciclo de instrução.

### Valor de design
- Documento de treinamento low-level para reduzir abstração e controlar latência.

---

## 2.7 `RAFAELIA_SEMENTES (1) (1).txt`

### Núcleos formais documentados
- Operador de contração `sqrt(3)/2` em Q16 como elemento recorrente.
- Ponto fixo de dinâmica linear afim.
- Hipóteses de dimensionalidade semântica e relações com entropia.

### Papel no projeto
- Base de pesquisa/ideação que alimenta constants/tunings em módulos computacionais.

---

## 3) Padrões arquiteturais identificados

1. **Freestanding-first**: entrada `_start`, syscalls/registradores explícitos, sem dependência obrigatória de runtime alto nível.
2. **Aritmética fixa (Q8/Q16)**: previsibilidade numérica e custo constante.
3. **Estado como bitmask**: composição semântica por operações booleanas, despacho rápido por tabela.
4. **Monólitos geradores**: arquivos que são simultaneamente documentação e fábrica de artefatos.

---

## 4) Contradições e gaps técnicos observados no diretório

- Arquivos em formatos mistos (markdown/texto/shell/código embutido), sem fronteira rígida de build source.
- Tipagem inconsistente entre fragmentos (`s64` em um arquivo sem typedef local).
- Alguns conteúdos são especificação conceitual e não código executável direto.
- Ausência de índice canônico do diretório com classificação “executável vs especificação”.

---

## 5) Recomendação de design documental (aplicada)

- Este documento passa a ser a referência técnica para:
  - leitura rápida de algoritmo por arquivo;
  - entendimento de contratos e invariantes;
  - distinção entre material executável e conceitual.

