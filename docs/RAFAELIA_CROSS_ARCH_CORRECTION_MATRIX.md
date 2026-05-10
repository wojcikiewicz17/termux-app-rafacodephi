# RAFAELIA Cross-Architecture Correction Matrix

## Objetivo

Este documento acompanha `tools/rafaelia_cross_arch/raf_cross_arch_modules.c` e corrige o bloco experimental multi-arquitetura sem ligar código instável ao APK Android. A regra é: **não quebrar o APK**; arquiteturas fora de Android ficam em laboratório isolado com smoke test host e probes opcionais por toolchain.

## Correções aplicadas ao bloco experimental

| Arquitetura | Correção de contrato | Motivo |
|---|---|---|
| RISC-V 32 | Mantido `a7=nr` e `a0-a5=args`; UART/MMIO não é fixado como se CH32V/GD32VF/ESP32-C3 fossem iguais. | Endereços periféricos variam por SoC; usar MMIO fixo em módulo genérico é bug lógico. |
| macOS ARM64/x86_64 | Separado Darwin/BSD de Linux: ARM64 usa `x16` + `svc #0x80`; x86_64 usa `rax=0x2000000|nr`. | macOS não usa ABI Linux nem ELF; código freestanding total não é equivalente ao Android/Linux. |
| MIPS O32 | Registradores documentados como `v0=nr`, `a0-a3=args`, `a3=errno flag`; endianness é decisão de toolchain. | O retorno de erro em MIPS O32 não é só `v0`; ignorar `a3` perde semântica de erro. |
| LoongArch64 | Mantido como ISA própria com `a7=nr`, `a0-a5=args`, `syscall 0`. | Não é MIPS; nomes de registradores e encoding são próprios. |
| s390x | Corrigido `write` Linux para syscall `1`, com `r1=nr` e `r2-r7=args`. | O bloco anterior confundia número de syscall de outras arquiteturas. |
| PowerPC | Tipos de 32 bits definidos e syscall isolada por `r0=nr`, `r3-r8=args`, `sc`. | O bloco anterior usava `u32` sem definição no ramo PPC32 e misturava largura. |

## Política de integração

- O laboratório em `tools/rafaelia_cross_arch/` **não é dependência de Gradle, NDK ou APK**.
- O smoke test compila no host usando fallbacks portáveis e só executa probes cross quando toolchains existem.
- Claims de performance, timers e MMIO continuam `NEEDS_BENCHMARK` até haver hardware/toolchain específico e logs reproduzíveis.
- Qualquer promoção futura para CI obrigatório deve ser feita por workflow separado, nunca dentro do caminho crítico de `:app:assemble*`.
