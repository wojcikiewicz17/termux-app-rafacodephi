# Documentação em Níveis (L)

## L0 — Visão do sistema (macro)
- Fork Termux com identidade própria (`com.termux.rafacodephi`).
- Compatibilidade Android 15/16 (inclui alinhamento para páginas de 16KB).
- Pipeline RAFAELIA com validações de bootstrap, hashes e trilha de release.
- Módulo nativo RMR (C/ASM + JNI fino com fallback C).
- Trilha de benchmark industrial no padrão Vectra para medir desempenho real, regressão e estabilidade sob carga.

## L1 — Domínios principais
- **Build & Toolchain**: Gradle, CMake, NDK, SDK/JDK, ABIs (`armeabi-v7a`, `arm64-v8a`, `x86_64`).
- **Bootstrap & Integridade**: preparação de bootstrap e verificação por hash (BLAKE3/SHA256).
- **Release & Signing**: trilha unsigned (validação interna) e trilha signed opt-in (variáveis explícitas).
- **Runtime Android**: side-by-side package, compatibilidade Android 12+ (phantom process) e 15/16.
- **Benchmarks Industriais Vectra**: medição reprodutível de CPU, memória, I/O, latência, jitter, cold/warm start, ABI, tamanho de APK, ELF/page-size, JNI, C/ASM e estabilidade runtime.
- **Documentação & Auditoria**: inventários, auditorias por módulo e guias técnicos.
- **Contrato Conceitual RAFAELIA**: mapa de transporte semântico para `T^7`, 42 ciclos, Hz/memória, multilíngue, integridade e política SDK/ABI.
- **Laboratório Cross-Arch Isolado**: correções RV32/macOS/MIPS/LoongArch/s390x/PPC em `tools/rafaelia_cross_arch/`, fora do caminho do APK.

## L2 — Árvore operacional mínima (o “tree L2”)

```text
[Build Local]
  ├─ ./scripts/ci_android_preflight.sh
  ├─ ./gradlew assembleDebug
  └─ ./scripts/diagnose.sh

[Release Local]
  ├─ eval "$(./scripts/prepare_bootstrap_env.sh --print-env)"  # compila bootstraps RAFCODEΦ locais por padrão
  ├─ ./scripts/build_release_artifacts.sh
  └─ ./scripts/build_apk_matrix.sh

[Bootstrap Contract]
  ├─ TERMUX_BOOTSTRAP_BLAKE3_AARCH64
  ├─ TERMUX_BOOTSTRAP_BLAKE3_ARM
  ├─ TERMUX_BOOTSTRAP_BLAKE3_I686
  └─ TERMUX_BOOTSTRAP_BLAKE3_X86_64

[Signing Contract (official release)]
  ├─ TERMUX_ENABLE_RELEASE_SIGNING=true
  ├─ TERMUX_RELEASE_KEYSTORE_FILE
  ├─ TERMUX_RELEASE_KEYSTORE_PASSWORD
  ├─ TERMUX_RELEASE_KEY_ALIAS
  └─ TERMUX_RELEASE_KEY_PASSWORD

[Native Contract]
  ├─ JNI bridge fino
  ├─ dispatch runtime por capacidade
  ├─ fallback C seguro
  └─ C/ASM otimizado quando disponível

[Industrial Benchmark Contract — Vectra-grade]
  ├─ build_metrics: clean/incremental build time, warnings, APK size, native .so size
  ├─ binary_metrics: SHA256, ABI matrix, ELF alignment, 16KB page-size validation
  ├─ runtime_metrics: cold start, warm start, shell spawn, JNI call overhead
  ├─ cpu_metrics: scalar C, branchless C, NEON/ASM path, fallback C path
  ├─ memory_metrics: RSS, Java heap, native heap, arena usage, allocation count
  ├─ io_metrics: sequential read/write, random 4K read/write, fsync latency
  ├─ stability_metrics: crash count, ANR count, signal 9/11, phantom process behavior
  ├─ jitter_metrics: p50/p90/p95/p99 latency, standard deviation, worst-case tail
  └─ artifacts: JSON, CSV, Markdown summary, SHA256SUMS, APK_SIZE_REPORT.tsv
```

## Estado do que já está pronto (nível L)
- Estrutura de fork e identidade side-by-side documentadas.
- Trilha de build debug/release local documentada com scripts prontos.
- Contrato de bootstrap com variáveis BLAKE3 definido.
- Contrato de signing oficial explícito e separado da trilha unsigned.
- Diretrizes de compatibilidade Android 15/16 e ABIs validadas declaradas.
- Inventário de documentação/auditoria já referenciado por módulo.
- Requisito de benchmark industrial Vectra-grade formalizado como item operacional L2.

## Próximo passo recomendado (L2 -> execução)
1. Rodar preflight.
2. Rodar assembleDebug.
3. Rodar matriz de release com e sem signing (quando credenciais existirem).
4. Validar artefatos por ABI e universal.
5. Implementar/rodar a suíte de benchmarks industriais Vectra-grade e publicar artefatos JSON/CSV/Markdown no CI.


## Contratos adicionais L2
- External Integrity Contract
- External Vectra Benchmark Contract
- Symbol Encoding Contract


## Certification and audit claim notice

This repository does not claim ISO certification, formal ISO compliance, or accredited external audit status. Any ISO/IEC references are internal checklist references or methodological alignment notes only. Certification requires an external accredited audit process and is outside the scope of this repository.

Este repositório não declara certificação formal baseada em ISO, conformidade ISO formal nem auditoria externa acreditada. Qualquer referência a ISO/IEC é apenas checklist interno, referência metodológica ou alinhamento preliminar de boas práticas. Certificação exige processo externo acreditado e está fora do escopo deste repositório.

### Audit/benchmark/runtime trail
- `docs/AUDIT_CLAIMS_POLICY.md`
- `reports/vectra_grade_benchmarks.md`
- `reports/device_runtime_smoke.md`
- `reports/rmr_equivalence.md`
- CI validação não equivale a validação em device real.
- Benchmark definido não equivale a benchmark medido.
