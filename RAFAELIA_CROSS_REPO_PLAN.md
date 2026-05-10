# RAFAELIA Cross-Repo Plan

## Repo atual
- `termux-app-rafacodephi`

## Repos externos relacionados (não alterados nesta execução)
1. `termux-packages` (upstream de bootstraps, referência operacional indireta)
2. `BLAKE3` (hash/integridade para contrato de bootstrap)
3. `Vectras-VM-Android` (integração de consumo de ambiente Termux)
4. `qemu_rafaelia` (execução externa por contrato de processo)
5. `androidx_RmR` (consumo de componentes AndroidX custom)

## Contrato esperado
- Bootstraps usados por `termux-app-rafacodephi` devem manter layout e conteúdo compatíveis com validações de runtime.
- Hashes BLAKE3 devem estar disponíveis para trilhas estritas de release.
- Integrações Vectras/QEMU devem acontecer por API/CLI/artefatos, sem mistura de código neste repositório.

## Arquivos envolvidos no repo atual
- `app/build.gradle`
- `scripts/rewrite_bootstrap.py`
- `scripts/prepare_bootstrap_env.sh` (referência operacional)

## Mudança necessária no outro repo (planejada)
- **termux-packages**: publicar/estabilizar metadados de layout dos bootstraps por ABI para reduzir suposições de caminho.
- **BLAKE3**: fornecer distribuição/documentação de hash tooling compatível com pipeline Android CI.
- **Vectras-VM-Android/qemu_rafaelia**: explicitar contrato de invocação (flags, env, artefatos esperados) em documento versionado.

## Por que não foi alterado agora
- Regra desta execução: alterar apenas o repositório local atual.

## Ordem recomendada para próxima execução do Codex
1. `termux-packages` (ou repo que mantém os zips bootstrap usados aqui), para formalizar contrato de layout.
2. `BLAKE3`, para fortalecer pipeline de hash reproduzível.
3. `Vectras-VM-Android`, para alinhar integração por contrato com este app.
4. `qemu_rafaelia`, para contrato de runtime/observabilidade sem acoplamento.
5. `androidx_RmR`, somente após mapear consumo real.
