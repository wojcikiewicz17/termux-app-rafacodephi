# Status Bootstrap Lowlevel Rafaelia

## Compila
- host-smoke (`make selftest`) no módulo experimental.
- freestanding experimental multi-arquitetura via `make arm-freestanding ARCH=<arch>`.

## Não compila / não implementado
- integração completa Android runtime sem libc no app principal.
- extração ZIP real (fora de escopo e proibido nesta fase).

## Corrigido
- hex inválidos substituídos por hex válidos.
- macro `RAF_LOG_WRN` adicionada.
- entry separado em `entry_arm64.S`.
- `RAF_TERMUX_PREFIX` configurável por macro.
- selftest expandido com vetores golden de CRC32C/FNV-1a.

## Experimental
- ZIPRAF apenas round-trip de formato próprio.
- sem substituir bootstrap real do Termux.
- workflow NDK dedicado com matrix para 6 arquiteturas:
  - arm32
  - arm64
  - x86
  - x86_64
  - riscv64
  - armv7a-neon

## Pode entrar na beta
- apenas como módulo isolado e opcional.

## Não pode entrar na beta
- qualquer substituição do fluxo real de `TermuxInstaller` / `bootstrap.zip`.

## Riscos
- confundir ZIPRAF com ZIP real.
- suporte de target pode variar por imagem/NDK; workflow agora registra skip explícito por arquitetura não suportada.

## Próximos passos
- adicionar entry ASM específico para arm32 se necessário.
- validar execução em dispositivo ARM64/ARM32 via shell de teste isolado.
