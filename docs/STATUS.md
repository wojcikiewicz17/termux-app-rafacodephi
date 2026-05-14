# STATUS (Fonte de Verdade de Build/Release)

> Última revisão: 2026-05-14 (UTC)

Este documento consolida o estado **real e verificável** do pipeline Android (Gradle + NDK + CI) desta fork.

## 1) Estado atual (pronto)

- ✅ Build Android configurado com `compileSdkVersion=35`, `targetSdkVersion=34`, `minSdkVersion=21`.  
- ✅ Toolchain nativa fixada: `ndkVersion=26.3.11579264` via `gradle.properties`.  
- ✅ Política canônica de ABI definida em fonte única (`gradle.properties`): `armeabi-v7a`, `arm64-v8a`, `x86_64` + `x86` opcional + universal habilitado.  
- ✅ Script de matriz local (`scripts/build_apk_matrix.sh`) produz artefatos **unsigned** e **signed**, valida assinatura e gera relatórios/checksums.  
- ✅ Workflow CI (`.github/workflows/apk_matrix_build.yml`) publica APKs e relatórios com separação de trilha `official` vs `internal`.

## 2) Contratos estruturais ativos

### ABI / Arquitetura
- ABIs obrigatórias para trilha de release: `armeabi-v7a` e `arm64-v8a`.
- `x86_64` e `x86` seguem política de compatibilidade/expansão, sem quebrar o contrato mínimo móvel (ARM32 + ARM64).

### Assinatura
- Trilha **official** exige segredo de assinatura oficial e bloqueia release sem assinatura válida.
- Trilha **internal** permite unsigned para validação, mantendo signed release obrigatório para ABIs críticas.

### Integridade de artefato
- `SHA256SUMS.txt`, `ARTIFACT_MANIFEST.txt`, `APK_SIZE_REPORT.tsv` e `APK_SIZE_DIFF_RELEASE.tsv` são gerados no diretório `dist/apk-matrix/`.
- `verifyReleaseContract` roda no CI antes de upload final.

## 3) O que ainda depende de execução no ambiente

- 🔶 A compilação real de APK (local/CI) depende de SDK/NDK/CMake provisionados no host.
- 🔶 A assinatura oficial depende de `OFFICIAL_*` secrets no GitHub Actions.

## 4) Fonte de verdade (arquivos canônicos)

- Build e versões Android/NDK: `gradle.properties`
- Matriz local signed/unsigned: `scripts/build_apk_matrix.sh`
- Pipeline de upload e contratos CI: `.github/workflows/apk_matrix_build.yml`
- Visão macro do projeto: `README.md`

## 5) Regra de manutenção deste status

Sempre atualizar este arquivo **após** mudanças em:
- versão de SDK/NDK/JDK,
- política de ABI,
- regras de assinatura,
- workflow de artefatos,
- contratos de validação de release.
