# BOOTSTRAP_LOWLEVEL_RAFAELIA Audit

Fonte: `BOOTSTRAP_LOWLEVEL_RAFAELIA.txt`.

## Classificação por seção
- Seção 1 (tipos): COMPILABLE_C
- Seção 2 (syscalls): COMPILABLE_AFTER_FIX
- Seção 3 (arena): COMPILABLE_C
- Seção 4 (mem/string/hash): COMPILABLE_C
- Seção 5 (log): COMPILABLE_AFTER_FIX
- Seção 6 (BITRAF): COMPILABLE_AFTER_FIX
- Seção 7 (RAFSTORE): COMPILABLE_AFTER_FIX
- Seção 8 (ZIPRAF): NEEDS_REAL_IMPLEMENTATION
- Seção 9 (cycle/policy): COMPILABLE_AFTER_FIX
- Seção 10 (main/integração Termux): TERMUX_INTEGRATION_UNSAFE
- Seção 11 (selftest): COMPILABLE_AFTER_FIX
- Seção 12 (entry): ASM_BLUEPRINT
- comentários gerais e roadmap: COMMENT_ONLY/PSEUDOCODE

## Erros objetivos identificados
1. Hex inválido: `0xRAF00001u`.
2. Seeds inválidos: `0xCPU_SEED_01ULL`, `0xRAM_SEED_02ULL`, `0xDSK_SEED_03ULL`.
3. Macro faltante: `RAF_LOG_WRN` usada sem definição.
4. Símbolos sem definição em blocos de integração.
5. Uso arriscado de SP em entry C (`raf_entry_c`) no blueprint.
6. Flags `-fno-pic`/`-static` conflitam com cenário Android PIE em app normal.
7. Confusão entre ZIPRAF experimental e ZIP real (`bootstrap.zip`).
8. Caminho fixo hardcoded com `com.termux`.
9. Selftests sem todos os golden values explícitos.
10. Trecho ASM comentado precisa virar `entry_arm64.S` real.
