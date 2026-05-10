# ARMÉ — Plano de Refatoração Total (C/ASM Freestanding)

## Escopo
Este diretório (`Arme/`) foi consolidado como área de estudo e transição para implementação **low-level freestanding**.

Objetivo técnico:
- remover fricção arquitetural;
- reduzir camadas de abstração desnecessárias;
- substituir legado gradualmente por artefatos C/ASM controlados;
- estabelecer trilha sem dependências externas e sem libc na etapa final de runtime.

## Estado atual
Os arquivos em `Arme/` são majoritariamente rascunhos conceituais e especificações textuais. Eles devem ser tratados como **fonte de requisitos** e não como build source final.

## Diretrizes de refatoração
1. **Baseline por módulo**
   - catalogar cada arquivo e extrair invariantes (entrada, saída, contrato, restrições).
2. **Normalização de contratos**
   - transformar texto livre em contratos explícitos (ABI, alinhamento, flags, registradores, calling convention).
3. **Migração incremental**
   - converter blocos para C freestanding e, em seguida, ASM quando houver ganho real de controle/tamanho/latência.
4. **Sem dependência de libc em runtime final**
   - rotinas essenciais devem usar syscall/NDK low-level apenas quando estritamente necessário.
5. **Validação por arquitetura**
   - arm32 e arm64 com contratos equivalentes de comportamento.

## Estrutura alvo sugerida
- `Arme/spec/` — especificações canônicas (ABI, memória, bootstrap, syscalls)
- `Arme/src/c/` — C freestanding de transição
- `Arme/src/asm/arm32/` — ASM armv7
- `Arme/src/asm/arm64/` — ASM aarch64
- `Arme/tests/contracts/` — testes de contrato (sem framework pesado)
- `Arme/docs/` — documentação técnica e de release

## Política de qualidade
- Nenhuma mudança entra sem contrato de entrada/saída explícito.
- Código novo precisa indicar alvo arquitetural (arm32/arm64).
- Divergência entre doc e código bloqueia merge.

## Fluxo GitHub recomendado
- Issues por módulo (`arme:abi`, `arme:bootstrap`, `arme:syscall`, `arme:asm-arm32`, `arme:asm-arm64`).
- Projects (board): Backlog → Spec Ready → In Refactor → Validated.
- Actions:
  - lint de documentação/contratos;
  - build matrix (arm32/arm64);
  - verificação de símbolos/exportação.

## Entregáveis mínimos por etapa
- **E1**: inventário técnico completo dos arquivos atuais.
- **E2**: especificações ABI/memória/símbolos em markdown versionado.
- **E3**: bootstrap freestanding mínimo compilando arm32+arm64.
- **E4**: módulos críticos migrados para ASM com validação de equivalência.
- **E5**: pacote release com trilhas signed/unsigned separadas e auditáveis.

## Observações
- A exigência de eliminar estruturas de controle em alto nível deve ser aplicada na etapa de ASM final.
- Para segurança/manutenibilidade, a transição via C freestanding é recomendada antes da eliminação total.
