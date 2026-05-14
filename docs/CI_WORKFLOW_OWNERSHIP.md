# CI Workflow Ownership Matrix

## Canonical workflows por trilha

| Trilha | Workflow canônico | Objetivo | ABIs | Política de assinatura | Artefatos |
|---|---|---|---|---|---|
| `official` | `.github/workflows/apk_matrix_build.yml` | Build oficial de release/debug com matriz completa e gates de contrato de release | `armeabi-v7a`, `arm64-v8a`, `universal` | `official` exige release assinado (`use_official_signing=true`), sem fallback implícito para artefato oficial | APKs signed/unsigned por ABI, relatórios de tamanho, checksums, manifest |
| `internal` | `.github/workflows/arme-benchmark.yml` | Benchmark low-level ARM com validação de manifesto | `armeabi-v7a`, `arm64-v8a` | não aplicável (benchmark) | relatórios de benchmark/manifesto |
| `debug` | `.github/workflows/run_tests.yml` | Testes unitários, smoke de bootstrap e inventário de código | host + validações Android | não aplicável (test lane) | relatórios de testes, inventário, logs de smoke |

## Workflows legados (deprecated)

Estes workflows permanecem temporariamente para compatibilidade, mas **não são fonte de verdade** e devem ser removidos até **2026-09-30**:

- `.github/workflows/apk_arm32_signed_unsigned.yml`
- `.github/workflows/apk_arm32_signed_unsigned_target29.yml`
- `.github/workflows/apk_matrix_artifacts_variants.yml`

Substituição estrutural: consolidar chamadas na matriz canônica (`apk_matrix_build.yml`) com trilha explícita.

## Contratos obrigatórios

Todo workflow novo/ativo em `.github/workflows/*.yml` deve declarar metadados no cabeçalho YAML (comentários):

- `ci_track: <debug|internal|official|ops|deprecated>`
- `ci_abis: <csv com ABIs ou n/a>`

Exemplo:

```yaml
# ci_track: official
# ci_abis: armeabi-v7a,arm64-v8a,universal
name: APK Matrix Build (signed + unsigned)
```

## Regra de segurança da trilha official

- A trilha `official` **não pode** depender de fallback implícito para assinatura de release oficial.
- Se secrets oficiais não estiverem disponíveis, o workflow deve falhar para a trilha `official`, nunca publicar artefato oficial assinado por chave local de validação.
