# Documentação em Níveis (L)

## L0 — Visão do sistema (macro)
- Fork Termux com identidade própria (`com.termux.rafacodephi`).
- Compatibilidade Android 15/16 (inclui alinhamento para páginas de 16KB).
- Pipeline RAFAELIA com validações de bootstrap, hashes e trilha de release.
- Módulo nativo RMR (C/ASM + JNI fino com fallback C).

## L1 — Domínios principais
- **Build & Toolchain**: Gradle, CMake, NDK, SDK/JDK, ABIs (`armeabi-v7a`, `arm64-v8a`, `x86_64`).
- **Bootstrap & Integridade**: preparação de bootstrap e verificação por hash (BLAKE3/SHA256).
- **Release & Signing**: trilha unsigned (validação interna) e trilha signed opt-in (variáveis explícitas).
- **Runtime Android**: side-by-side package, compatibilidade Android 12+ (phantom process) e 15/16.
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
  ├─ C/ASM otimizado quando disponível
  ├─ docs/RAFAELIA_CONCEPT_CARRY_MAP.md como contrato antes de tocar claims complexos
  ├─ docs /RAFAELIA_CONCEPT_CARRY_MAP.md como contrato antes de tocar claims complexos
  └─ scripts/build_rafaelia_bootstraps.sh antes do ASM incbin do APK
```

## Estado do que já está pronto (nível L)
- Estrutura de fork e identidade side-by-side documentadas.
- Trilha de build debug/release local documentada com scripts prontos.
- Contrato de bootstrap com variáveis BLAKE3 definido.
- Contrato de signing oficial explícito e separado da trilha unsigned.
- Diretrizes de compatibilidade Android 15/16 e ABIs validadas declaradas.
- Inventário de documentação/auditoria já referenciado por módulo.

## Próximo passo recomendado (L2 -> execução)
1. Rodar preflight.
2. Rodar assembleDebug.
3. Rodar matriz de release com e sem signing (quando credenciais existirem).
4. Validar artefatos por ABI e universal.
