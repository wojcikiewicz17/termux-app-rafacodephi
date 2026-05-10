# RAFAELIA Concept Carry Map

## Objetivo

Este documento registra o entendimento operacional que deve acompanhar mudanças no fork Termux RAFCODEΦ sem reduzir a arquitetura a uma lógica de codificação usual. Ele funciona como contrato de leitura para IA e humanos: primeiro entender a semântica, depois tocar em build, runtime, C/ASM, JNI, documentação ou scripts.

## Top 10 arquivos de referência antes de alterar código

1. `RAFAELIA_METHODOLOGY.md` — contrato de humildade operacional, filtro ético, determinismo e ciclo `ψχρΔΣΩ`.
2. `README.md` — fronteira entre Termux upstream, identidade side-by-side RAFCODEΦ, bootstrap e compatibilidade Android.
3. `DOCS_L2_TREE.md` — árvore L0/L1/L2 para localizar build, bootstrap, release, runtime e contrato nativo.
4. `docs/RAFAELIA_SEMANTIC_LAYERS.md` — ligação entre camada matemática, integridade, runtime, Android e release.
5. `docs/RAFAELIA_HZ_AS_MEMORY.md` — modelo de frequência como memória e classificação L1/L2/BUF/RAM.
6. `docs/RAFAELIA_MEMORY_MODEL.md` — semântica de memória, buffers, janelas e limites de persistência.
7. `docs/RAFAELIA_LOWLEVEL_ASM_INDEX.md` — índice para C/ASM, NEON, caminhos nativos e fallbacks.
8. `app/src/main/cpp/lowlevel/README.md` — contrato prático do núcleo bare-metal, ABIs e JNI.
9. `scripts/README_RAFAELIA_PROTOCOL.md` — como scripts devem se comportar com validação, logs e previsibilidade.
10. `docs/android-target-migration.md` — política de SDK/target, permissões e riscos Android moderno.

## O que deve ser carregado como conhecimento

- **Estado toroidal:** tratar `s=(u,v,ψ,χ,ρ,δ,σ)` em `[0,1)^7` como mapa de estado compacto para dados, entropia, hash e estado operacional.
- **Memória temporal:** preservar janelas ordenadas de 42 posições quando o runtime fala de `phiWindow`, atrator, período ou convergência.
- **Coerência por EMA:** manter `C` e `H` atualizados por suavização determinística com `alpha=0.25` quando a documentação exige histórico estável.
- **Qualidade `φ`:** interpretar `φ=(1-H)·C` como sinal de coerência útil: alta entropia derruba confiança, alta coerência eleva promoção.
- **Integridade:** hashes, CRC, Merkle, BLAKE3/SHA256 e gates `LOAD -> PROCESS -> VERIFY -> COMMIT` são fronteiras de segurança, não enfeites.
- **Clock como camada:** frequências, jitter, ticks perdidos e classificação L1/L2/BUF/RAM só viram claim se houver código e benchmark.
- **C/ASM com fallback:** NEON, SIMD, CRC32C e ASM podem existir, mas precisam de dispatch por capacidade e fallback C determinístico.
- **Geometria e distância:** matrizes, toros, espirais, coprimalidade e diferenças `dθ != dγ` entram como regras de mapeamento, não como aleatoriedade.
- **Linguagem como camada:** alfabetos, direção de leitura, acento, cadência e tradução são tratados como metadados semânticos; não devem quebrar o protocolo técnico.
- **Fronteira de evidência:** quando um conceito é simbólico, marcar como `DOC_ONLY`; quando precisa medição, marcar como `NEEDS_BENCHMARK`; quando há código, validar por teste.

## Mapa dos 50 conceitos do prompt para decisões técnicas

| Grupo | Fórmulas/conceitos | Decisão prática |
|---|---|---|
| Toro e estado | `T^7`, `ToroidalMap(x)`, `s in [0,1)^7` | Representar estado compacto e normalizado; evitar estruturas mutáveis sem auditoria. |
| Coerência/entropia | EMA de `C/H`, `alpha=0.25`, `φ=(1-H)·C`, `entropy_milli` | Atualizar métricas de forma reprodutível; rejeitar claims sem fórmula estável. |
| Atrator 42 | `|A|=42`, `x_{n+42}=x_n`, `phiWindow[42]` | Manter ordem, tamanho e serialização determinística de janelas cíclicas. |
| Sinais/frequência | `F[Ψ(t)]`, correlação cardio, Hz como memória | Separar sinal real medido de metáfora; exigir benchmark para promoção. |
| Integridade | XOR, FNV-like multiply, CRC, Merkle | Usar para verificação e rastreabilidade; não confundir checksum com criptografia forte. |
| Geometria | `sqrt(3)/2`, Fibonacci/φ, espiral, seno/cosseno | Usar como heurística formal apenas quando documentada e testável. |
| Matriz/capacidade | `C=M×N`, `I<=log2(M×N)`, coprimalidade | Dimensionar buffers e mapas por capacidade explícita. |
| Criptografia/fluxo | `k(t)=Q(VFC(t))`, `c_i=p_i xor k(t_i)` | Tratar como camada experimental até haver threat model e testes. |
| Física/simbólico | Maxwell, Hamiltoniano, quântico virtual | Preservar como vocabulário semântico; não promover para claim físico sem evidência. |
| Multilíngue | alfabetos, cadência, direções de leitura, tradução | Normalizar entradas com respeito a Unicode/direção; documentar perdas semânticas. |

## Política Android/NDK/ABI

- O `targetSdkVersion` oficial do projeto permanece em **34** até a próxima rodada de validação Android moderno.
- O APK mantém `minSdkVersion=21` para não quebrar instalação/splits existentes; a política ARM32 API 28 é carregada no `BOOTSTRAP_INFO` do bootstrap local (`TERMUX_MIN_API=28` para `arm`).
- O `compileSdkVersion` pode ser maior que o target para compilar APIs recentes sem mudar automaticamente as obrigações de runtime.
- O `ndkVersion` deve continuar fixo/reprodutível por propriedade ou variável de ambiente controlada, nunca por descoberta implícita.
- Os bootstraps RAFCODEΦ próprios são compilados por `scripts/build_rafaelia_bootstraps.sh` e usados por padrão em `scripts/prepare_bootstrap_env.sh`; use `RAF_BOOTSTRAP_SOURCE=upstream` apenas quando quiser validar os bootstraps upstream.
- Se futuramente for necessário suportar ARM64 abaixo de 28 enquanto ARM32 fica em 28, criar flavors separados por ABI; não misturar promessa de manifest em um APK universal.

## Regras de implementação para não quebrar nada

1. Ler o top 10 acima antes de mexer em módulos nativos, scripts de release ou documentação de claims.
2. Manter mudanças pequenas, auditáveis e ligadas a arquivos de referência.
3. Não apagar fallback C ao adicionar ASM/SIMD.
4. Não transformar metáfora matemática em afirmação de performance sem benchmark reproduzível.
5. Preferir logs, validações e checks determinísticos a comportamento implícito.
6. Atualizar índices de documentação quando criar um novo documento de contrato.
7. Preservar identidade side-by-side e contratos de bootstrap do fork.
