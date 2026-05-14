# Build APK Matrix (ARM32 + ARM64, signed + unsigned)

## Objetivo
Executar uma trilha única que:
1. compila APKs debug/release,
2. garante ABIs obrigatórias (`armeabi-v7a` e `arm64-v8a`),
3. assina releases localmente (validação),
4. valida assinatura,
5. gera manifest e checksums para auditoria.

## Pré-requisitos
- JDK compatível com Gradle do projeto.
- Android SDK/NDK/CMake instaláveis por `scripts/setup_android_toolchain.sh`.
- Ambiente shell POSIX com `bash`, `awk`, `sed`, `find`, `xargs`, `sha256sum`, `keytool`.

## Execução

```bash
./scripts/build_apk_matrix.sh
```

## Etapas internas executadas pelo script

1. Provisiona SDK/NDK/CMake (`setup_android_toolchain.sh`).
2. Carrega hashes BLAKE3 de bootstrap (`prepare_bootstrap_env.sh --print-env`).
3. Executa testes unitários debug (`:app:testDebugUnitTest`).
4. Compila `assembleDebug` e `assembleRelease` com split APK habilitado.
5. Verifica presença de APK por ABI obrigatória.
6. Assina APKs de release (`apksigner`) em `dist/apk-matrix/signed/`.
7. Verifica assinatura dos APKs assinados.
8. Emite relatórios de tamanho e checksums.

## Saídas esperadas

Diretório: `dist/apk-matrix/`

- `unsigned/*.apk`
- `signed/*-signed.apk`
- `SHA256SUMS.txt`
- `APK_SIZE_REPORT.tsv`
- `APK_SIZE_DIFF_RELEASE.tsv`
- `ARTIFACT_MANIFEST.txt`

## Critérios de falha (hard fail)

- Hash BLAKE3 ausente/inválido para qualquer bootstrap exigido.
- Falta de APK `armeabi-v7a` ou `arm64-v8a` na saída unsigned.
- Falta de APK de release assinado para `armeabi-v7a` ou `arm64-v8a`.
- `apksigner verify` falhar em qualquer release assinado.

## Relação com o CI

No GitHub Actions (`apk_matrix_build.yml`):
- trilha `official` reforça secrets obrigatórios e assinatura oficial;
- trilha `internal` permite upload unsigned de release para validação;
- `verifyReleaseContract` valida contrato antes do upload final.
