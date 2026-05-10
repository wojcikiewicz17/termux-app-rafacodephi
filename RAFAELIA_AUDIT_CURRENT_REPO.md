# RAFAELIA Audit — Current Repo

- **Data**: 2026-05-10
- **Repo atual**: `termux-app-rafacodephi`
- **Branch atual**: `work`
- **Commit base auditado**: `f4fac08a13d4411ff610cfb3680e82b93bbdfe00`

## 1) Sistema de build detectado
- Gradle multi-módulo Android (`settings.gradle`: `app`, `termux-shared`, `terminal-emulator`, `terminal-view`, `rafaelia`, `rmr`).
- NDK Build (`Android.mk`) acionado em módulos com código nativo.
- Scripts auxiliares de preflight/bootstrap (`scripts/ci_android_preflight.sh`, `scripts/rewrite_bootstrap.py`).

## 2) Linguagens principais
- Kotlin/Java (Android app e bibliotecas).
- C/C++ e ASM (JNI/NDK, bootstrap e módulos nativos).
- Shell + Python (orquestração de build/bootstrap).

## 3) ABIs/plataformas declaradas
- Matriz principal: `armeabi-v7a`, `arm64-v8a`, `x86_64`.
- ABI opcional: `x86`.
- Meta declarada: Android 15/16 com page size 16KB (via flags e documentação).

## 4) Arquivos críticos inspecionados
- `README.md`
- `build.gradle`
- `settings.gradle`
- `app/build.gradle`
- `scripts/ci_android_preflight.sh`
- `scripts/rewrite_bootstrap.py`

## 5) Build baseline (comandos executados e resultado real)
1. `./gradlew tasks --all`
   - **Falha inicial**: `SDK location not found` (sem `local.properties` válido).
2. `./scripts/ci_android_preflight.sh`
   - **Passou**: bootstrapou command-line tools Android em `/root/Android/Sdk` e gravou `sdk.dir` em `local.properties`.
3. `./gradlew tasks --all`
   - **Passou** após preflight.
4. `./gradlew :app:assembleDebug`
   - **Falha 1 (causa-raiz)**: `FileNotFoundError: 'file'` dentro de `scripts/rewrite_bootstrap.py`.
   - **Correção aplicada**: fallback quando utilitário `file` não existe.
5. `./gradlew :app:assembleDebug` (reexecução)
   - **Falha 2 (causa-raiz)**: validação rígida assumia somente `bin/sh` e `bin/pkg`; bootstrap atual não confirmou esses caminhos exatos.
   - **Correção aplicada**: validação passou a aceitar também `usr/bin/sh` e `usr/bin/pkg`.
   - **Status atual**: precisa nova rodada completa para confirmar build final pós-correção.

## 6) Riscos imediatos
- Build debug depende do pipeline de reescrita de bootstrap; mudanças no layout dos zips upstream podem quebrar validações rígidas.
- `TERMUX_BOOTSTRAP_BLAKE3_*` ausentes mantêm trilha debug em modo não-runtime-ready (esperado), release estrito permanece bloqueado por design.
- Build release assinado depende de material de keystore via variáveis de ambiente (não disponível neste ambiente).

## 7) Comandos de build/test disponíveis
- `./gradlew tasks --all`
- `./gradlew :app:assembleDebug`
- `./gradlew :app:assembleRelease` (unsigned por padrão se signing não habilitado)
- `./gradlew verifyReleaseContract`
- `./scripts/ci_android_preflight.sh`

## 8) Relação com ecossistema (5 repositórios)
- `termux-app-rafacodephi` (atual): orquestrador Android/Termux e bootstrap runtime.
- `Vectras-VM-Android`: consumidor potencial de ambiente/integração Android; contrato deve ser por artefatos/versionamento, não código colado.
- `androidx_RmR`: fonte externa de componentes AndroidX customizados; requer pinagem de versão/commit para consumo seguro.
- `BLAKE3`: base de integridade/hash para trilhas de bootstrap/release; integração deve permanecer verificável e mensurável.
- `qemu_rafaelia`: runtime de emulação externo; interação com Termux deve ser por contrato de processo/artefato, sem acoplamento estrutural neste repo.

## 9) Correções mínimas aplicadas nesta execução
- Robustez no `scripts/rewrite_bootstrap.py` para ambientes CI/dev sem utilitário Unix `file`.
- Validação de binários runtime no bootstrap tornada compatível com variação de layout (`bin/*` e `usr/bin/*`).

## 10) Resultado medido vs não medido
- **Medido**: `tasks` Gradle passou após preflight; `assembleDebug` avançou além da falha original (`file` ausente).
- **Não medido**: APK final debug/release após última correção; release assinado; validação em dispositivo ARM32/ARM64 real; benchmark de performance.

