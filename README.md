# Termux Application - RafaCodePhi Fork

> 📚 **Mapa rápido em nível L/L2**: veja [`DOCS_L2_TREE.md`](./DOCS_L2_TREE.md).

## Fork Notice and Attribution

**This is a fork of the original [Termux](https://github.com/termux/termux-app) project.**

### Original Project
- **Original Repository**: [termux/termux-app](https://github.com/termux/termux-app)
- **Original Authors**: The Termux team and contributors
- **Original License**: GPLv3 (with exceptions as detailed in LICENSE.md)
- **Website**: [https://termux.com](https://termux.com)

### Fork Information
- **Fork Maintained By**: instituto-Rafael
- **Fork Repository**: [instituto-Rafael/termux-app-rafacodephi](https://github.com/instituto-Rafael/termux-app-rafacodephi)
- **Purpose**: Enhanced version with additional features and customizations

### Legal Notice
This fork complies with the GPLv3 license of the original Termux project. All modifications and additions are also released under GPLv3 (unless otherwise specified). We acknowledge and respect the intellectual property rights of the original Termux developers and all contributors to the upstream project.

---

[![Build status](https://github.com/termux/termux-app/workflows/Build/badge.svg)](https://github.com/termux/termux-app/actions)
[![Testing status](https://github.com/termux/termux-app/workflows/Unit%20tests/badge.svg)](https://github.com/termux/termux-app/actions)
[![Join the chat at https://gitter.im/termux/termux](https://badges.gitter.im/termux/termux.svg)](https://gitter.im/termux/termux)
[![Join the Termux discord server](https://img.shields.io/discord/641256914684084234.svg?label=&logo=discord&logoColor=ffffff&color=5865F2)](https://discord.gg/HXpF69X)
[![Termux library releases at Jitpack](https://jitpack.io/v/termux/termux-app.svg)](https://jitpack.io/#termux/termux-app)

## About Termux

[Termux](https://termux.com) is an Android terminal application and Linux environment.

Note that this repository is for the app itself (the user interface and the terminal emulation). For the packages installable inside the app, see [termux/termux-packages](https://github.com/termux/termux-packages).

Quick how-to about Termux package management is available at [Package Management](https://github.com/termux/termux-packages/wiki/Package-Management). It also has info on how to fix **`repository is under maintenance or down`** errors when running `apt` or `pkg` commands.

**We are looking for Termux Android application maintainers.**

***

**NOTICE: Termux may be unstable on Android 12+.** Android OS will kill any (phantom) processes greater than 32 (limit is for all apps combined) and also kill any processes using excessive CPU. You may get `[Process completed (signal 9) - press Enter]` message in the terminal without actually exiting the shell process yourself. Check the related issue [#2366](https://github.com/termux/termux-app/issues/2366), [issue tracker](https://issuetracker.google.com/u/1/issues/205156966), [phantom cached and empty processes docs](https://github.com/agnostic-apollo/Android-Docs/blob/master/en/docs/apps/processes/phantom-cached-and-empty-processes.md) and [this TL;DR comment](https://github.com/termux/termux-app/issues/2366#issuecomment-1237468220) on how to disable trimming of phantom and excessive CPU usage processes. A proper docs page will be added later. An option to disable the killing should be available in Android 12L or 13, so upgrade at your own risk if you are on Android 11, especially if you are not rooted.

***


## Fork Contract: Upstream vs RAFCODEΦ

### A) Termux Upstream (base)
- Este repositório mantém o app Termux como base upstream (UI, terminal e integração padrão).
- Pacotes do ecossistema continuam referenciando o fluxo `termux-packages`.

### B) Alterações RAFCODEΦ
- Identidade side-by-side própria: `com.termux.rafacodephi`.
- Pipeline RAFAELIA com preparação explícita de bootstrap e validações de contrato.

### C) Módulo low-level RMR
- Módulo nativo C/ASM com JNI fino, fallback C e dispatch runtime por capacidades.
- Sem promessa de ganho de performance sem benchmark reproduzível.

### D) Compatibilidade Android 15/16
- Binários nativos com alinhamento para page size 16KB via linker flags.
- ABIs validadas na trilha de build: `armeabi-v7a`, `arm64-v8a`, `x86_64` (e universal quando gerado).

### E) Bootstrap e Signing
- Bootstraps obrigatórios e hashes BLAKE3 verificados antes de builds críticos.
- Signing oficial é opt-in e separado da trilha unsigned interna de validação.


## Canonical ABI Policy

Fonte única oficial: `gradle.properties`.

- `termux.abi.matrix=armeabi-v7a,arm64-v8a,x86_64` (ABIs obrigatórias)
- `termux.abi.optional=x86` (ABI opcional de compatibilidade)
- `termux.abi.universal=true` (universal APK quando gerado)

Contratos:
- `app/build.gradle` e `terminal-emulator/build.gradle` consomem essa política via `project.findProperty(...)`.
- Scripts operacionais (`scripts/build_apk_matrix.sh`, `scripts/bootstrap_lowlevel_sync_check.sh`) validam ABIs obrigatórias a partir da mesma fonte.
- CI valida consistência com `scripts/validate_abi_policy_consistency.sh`.

> Histórico: documentos legados em `COMP/` podem conter políticas ABI antigas (ex.: arm64-only). Eles são referência histórica e não definem a política vigente.

## 🚀 Termux RAFCODEΦ - Android 15/16 Ready

**This fork is fully compatible with Android 15/16 and can be installed side-by-side with official Termux.**

### ⚡ Critical Android 16 Fix Applied

**✅ 16KB Page Size Compatibility** - This build includes the critical fix for Android 15/16 devices with 16KB memory pages. The app **will NOT crash** on:
- Android 15 with 16KB pages enabled
- Android 16 Beta (all devices)
- Devices with kernel 5.15.178+ (like RMX3834)

Without this fix, apps crash with SIGSEGV on startup. **This fork includes the compatibility patch; validate in your own environment before production release.**

📖 See [Android 16 Page Size Fix Documentation](./ANDROID16_PAGE_SIZE_FIX.md) for technical details.

### Key Features
- ✅ **Package Name**: `com.termux.rafacodephi` (unique, no conflicts)
- ✅ **App Name**: `Termux RAFCODEΦ` (distinct branding)
- ✅ **Side-by-Side**: Install alongside official Termux without conflicts
- ✅ **Android 15/16**: Configured for 16KB page alignment and Phantom Process Killer handling
- ✅ **Zero Collisions**: Unique authorities, permissions, and data directories
- ✅ **Bare-Metal**: NEON/SIMD optimized native code with pthread support

### RMR Low-Level Module (C/ASM)
- ✅ **Low-level utilities**: Deterministic helpers implemented in C with ASM-backed primitives where possible (RMR module)
- ✅ **No legacy abstractions**: JNI only as a thin bridge to native primitives
- ✅ **Termux packages alignment**: The package ecosystem remains defined by [termux/termux-packages](https://github.com/termux/termux-packages)

### Quick Start

```bash
# Optional preflight (installs SDK/NDK from gradle.properties and writes local.properties sdk.dir)
# The resolver checks ANDROID_HOME/ANDROID_SDK_ROOT first, then common SDK paths:
# ~/Android/Sdk, /usr/local/lib/android/sdk, /opt/android-sdk, /opt/android-sdk-linux
./scripts/ci_android_preflight.sh

# Build
./gradlew assembleDebug

# Install
adb install app/build/outputs/apk/debug/termux-app_apt-android-7-debug_universal.apk

# Diagnose
./scripts/diagnose.sh
```

### Build/release pipeline local (bootstrap + BLAKE3)

Para manter a mesma coerência do CI RAFAELIA localmente:

```bash
# Prepara SDK/NDK, baixa bootstraps e exporta hashes BLAKE3
# para o shell atual.
eval "$(./scripts/prepare_bootstrap_env.sh --print-env)"

# Build debug/release (split APKs habilitado)
./scripts/build_release_artifacts.sh

# Matriz completa de artefatos + assinatura local auxiliar + SHA256
./scripts/build_apk_matrix.sh
```

Variáveis exportadas por `prepare_bootstrap_env.sh`:

- `TERMUX_BOOTSTRAP_BLAKE3_AARCH64`
- `TERMUX_BOOTSTRAP_BLAKE3_ARM`
- `TERMUX_BOOTSTRAP_BLAKE3_I686`
- `TERMUX_BOOTSTRAP_BLAKE3_X86_64`

Release signing oficial é opcional e controlado por:

- `TERMUX_ENABLE_RELEASE_SIGNING`
- `TERMUX_RELEASE_KEYSTORE_FILE`
- `TERMUX_RELEASE_KEYSTORE_PASSWORD`
- `TERMUX_RELEASE_KEY_ALIAS`
- `TERMUX_RELEASE_KEY_PASSWORD`

### Contrato de trilhas de release (CI)

| Trilha | Assinatura release (`armeabi-v7a`, `arm64-v8a`) | Unsigned permitido | Bloqueios |
|---|---|---|---|
| oficial | Obrigatória em `dist/apk-matrix/signed` | Não | Falha se faltar APK assinado por ABI, se houver release unsigned, se hash/nome divergirem de `SHA256SUMS.txt`, ou se `BOOTSTRAP_BAREMETAL_STRICT!=true`. |
| interna | Obrigatória em `dist/apk-matrix/signed` | Sim, apenas para validação explícita em `dist/apk-matrix/unsigned` | Falha se nomes de signed/unsigned violarem contrato ou se hashes não baterem com `SHA256SUMS.txt`. |

Validação única de contrato executada por `./gradlew verifyReleaseContract` antes de qualquer upload de artefato no workflow `apk_matrix_build.yml`.

O módulo nativo mantém dispatch runtime com fallback C seguro para ARM32/ARM64 quando NEON ASM não estiver disponível em runtime.

### Requisitos mínimos para scripts de sincronização/export

Os scripts de metadados Termux desta fork não dependem mais de Python e usam um utilitário C autoral em `rafaelia/src/main/cpp/tools/`.

- `bash`
- `git`
- `cc` (clang ou gcc com suporte a C99)
- `sed` e `awk` (ferramentas POSIX usuais do sistema)

Uso:

```bash
# Regerar rafaelia/src/main/cpp/raf_termux_packages.c via template determinístico
./scripts/sync_termux_packages.sh

# Exportar manifests .rafpkg e INDEX.rafidx
./scripts/export_termux_package_manifests.sh
```

### Documentation
- 🔥 [**Android 16 Page Size Fix**](./ANDROID16_PAGE_SIZE_FIX.md) - **Critical fix for Android 15/16 stability**
- 🚀 [**Boosters de Performance**](./BOOSTERS.md) - **6 tipos de boosters, detalhes técnicos, benchmarks**
- 🚀 [**Performance Boosters Guide**](./BOOSTERS_DOCUMENTACAO.md) - **Complete guide on SIMD boosters, types, and benchmarks**
- 📊 [**Benchmarks & Comparison**](./BENCHMARKS_COMPARISON.md) - **30+ metrics, side-by-side comparison, innovations**
- 📄 [Android 15 Audit Report](./ANDROID15_AUDIT_REPORT.md) - Complete audit and status
- 📚 [Android 15 Compatibility Guide](./docs/RAFCODEPHI_ANDROID15_COMPATIBILITY.md) - Technical documentation
- 🔧 [Troubleshooting Guide](./TROUBLESHOOTING.md) - Common issues and solutions
- 📝 [Changes and Patch](./docs/MUDANCAS_ANDROID15.md) - Detailed changelog
- ⚙️ [Bare-Metal Implementation](./IMPLEMENTACAO_BAREMETAL.md) - Native code optimizations
- 📖 [Complete Documentation](./DOCUMENTACAO.md) - Full technical documentation
- 🧩 [Total Dependencies Inventory](./docs/DEPENDENCIAS_TOTAIS.md) - Consolidated Gradle/modules dependencies
- 🗂️ [Loose Files Inventory](./ARQUIVOS_SOLTOS_INVENTARIO.md) - Audit of `.md` and root loose files
- 🔗 [External Integration Map](./docs/EXTERNAL_INTEGRATION_MAP.md)
- 🔗 [Symbol Encoding Policy](./docs/SYMBOL_ENCODING_POLICY.md)

***

## Contents
- [Fork Notice and Attribution](#fork-notice-and-attribution)
- [Termux RAFCODEΦ - Android 15 Ready](#-termux-rafcodeφ---android-15-ready)
- [Termux App and Plugins](#termux-app-and-plugins)
- [Installation](#installation)
- [Uninstallation](#uninstallation)
- [Important Links](#important-links)
- [Debugging](#debugging)
- [For Maintainers and Contributors](#for-maintainers-and-contributors)
- [Forking](#forking)
- [Sponsors and Funders](#sponsors-and-funders)
- [Acknowledgments and Attribution](#acknowledgments-and-attribution)
---




## Auditoria de documentação

- Relatório da raiz: [AUDITORIA.md](./AUDITORIA.md)
- Relatório do módulo MVP: [mvp/AUDITORIA.md](./mvp/AUDITORIA.md)
- Relatório do módulo RMR: [rmr/AUDITORIA.md](./rmr/AUDITORIA.md)
- Relatório de docs RAFAELIA: [docs/rafaelia/AUDITORIA.md](./docs/rafaelia/AUDITORIA.md)
- Relatório do legado RAFAELIA: [rafaelia/old/AUDITORIA.md](./rafaelia/old/AUDITORIA.md)
- Mapa absoluto de markdowns: [docs/MARKDOWN_MAPA_ABSOLUTO.md](./docs/MARKDOWN_MAPA_ABSOLUTO.md)
- Revisão completa de markdowns: [docs/REVISAO_COMPLETA_MARKDOWN.md](./docs/REVISAO_COMPLETA_MARKDOWN.md)
- Top 10 MD (código ↔ documentação): [docs/TOP10_CODE_DOC_GAPS_2026-05.md](./docs/TOP10_CODE_DOC_GAPS_2026-05.md)

***

## Termux App and Plugins

The core [Termux](https://github.com/termux/termux-app) app comes with the following optional plugin apps.

- [Termux:API](https://github.com/termux/termux-api)
- [Termux:Boot](https://github.com/termux/termux-boot)
- [Termux:Float](https://github.com/termux/termux-float)
- [Termux:Styling](https://github.com/termux/termux-styling)
- [Termux:Tasker](https://github.com/termux/termux-tasker)
- [Termux:Widget](https://github.com/termux/termux-widget)
---



## Installation

Upstream reference version cited here is `v0.118.3`; this fork currently declares `0.118.0-rafacodephi` in `app/build.gradle`.

**NOTICE: It is highly recommended that you update to `v0.118.0` or higher ASAP for various bug fixes, including a critical world-readable vulnerability reported [here](https://termux.github.io/general/2022/02/15/termux-apps-vulnerability-disclosures.html). See [below](#google-play-store-experimental-branch) for information regarding Termux on Google Play.**

Termux can be obtained through various sources listed below for **only** Android `>= 7` with full support for apps and packages.

Support for both app and packages was dropped for Android `5` and `6` on [2020-01-01](https://www.reddit.com/r/termux/comments/dnzdbs/end_of_android56_support_on_20200101/) at `v0.83`, however it was re-added just for the app *without any support for package updates* on [2022-05-24](https://github.com/termux/termux-app/pull/2740) via the [GitHub](#github) sources. Check [here](https://github.com/termux/termux-app/wiki/Termux-on-android-5-or-6) for the details.

The APK files of different sources are signed with different signature keys. The `Termux` app and all its plugins use the same [`sharedUserId`](https://developer.android.com/guide/topics/manifest/manifest-element) `com.termux` and so all their APKs installed on a device must have been signed with the same signature key to work together and so they must all be installed from the same source. Do not attempt to mix them together, i.e do not try to install an app or plugin from `F-Droid` and another one from a different source like `GitHub`. Android Package Manager will also normally not allow installation of APKs with different signatures and you will get errors on installation like `App not installed`, `Failed to install due to an unknown error`, `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, `INSTALL_FAILED_SHARED_USER_INCOMPATIBLE`, `signatures do not match previously installed version`, etc. This restriction can be bypassed with root or with custom roms.

If you wish to install from a different source, then you must **uninstall any and all existing Termux or its plugin app APKs** from your device first, then install all new APKs from the same new source. Check [Uninstallation](#uninstallation) section for details. You may also want to consider [Backing up Termux](https://wiki.termux.com/wiki/Backing_up_Termux) before the uninstallation so that you can restore it after re-installing from Termux different source.

In the following paragraphs, *"bootstrap"* refers to the minimal packages that are shipped with the `termux-app` itself to start a working shell environment. Its zips are built and released [here](https://github.com/termux/termux-packages/releases).

For local builds in this repository, bootstrap ZIPs under `app/src/main/cpp/bootstrap-*.zip` are **build artifacts** generated by Gradle tasks (for example `:app:downloadBootstraps`) and are intentionally not versioned in git.

If your local environment only has upstream bootstrap archives (without `BOOTSTRAP_INFO` for this fork), you can use an **explicit debug-only validation track**:

```bash
./gradlew assembleDebug
```

`upstream-debug-compat` is blocked for release tasks by design.

### Hotfix build ("até compilar")

Para destravar rapidamente a cadeia completa local (SDK + hashes bootstrap + APK unsigned/signed), execute:

```bash
./scripts/hotfix_ate_compilar.sh
```

Modos:

- padrão: executa `build_apk_matrix` (já inclui preflight, hashes, testes, assemble e assinatura local de validação).
- `--full`: força as etapas explícitas de preflight+hashes+assemble e depois roda a matriz.
- `--assemble-only`: roda apenas preflight+hashes+assemble.

O script preserva o contrato oficial de release: quando não há secrets oficiais, a assinatura usada em `dist/apk-matrix/signed/` é somente de validação interna.

### Release build signing (signed or unsigned)

`assembleRelease` now supports two explicit modes:

1. **Unsigned release (default)**: do not set `TERMUX_ENABLE_RELEASE_SIGNING`; Gradle will produce unsigned release artifacts.
2. **Signed release (explicit opt-in)**: set all variables below and `TERMUX_ENABLE_RELEASE_SIGNING=true`.

Required variables for signed release:

- `TERMUX_RELEASE_KEYSTORE_FILE`
- `TERMUX_RELEASE_KEYSTORE_PASSWORD`
- `TERMUX_RELEASE_KEY_ALIAS`
- `TERMUX_RELEASE_KEY_PASSWORD`

GitHub Actions can configure these automatically via `scripts/setup_android_signing.sh` when secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` are present.

### F-Droid

Termux application can be obtained from `F-Droid` from [here](https://f-droid.org/en/packages/com.termux/).

You **do not** need to download the `F-Droid` app (via the `Download F-Droid` link) to install Termux. You can download the Termux APK directly from the site by clicking the `Download APK` link at the bottom of each version section.

It usually takes a few days (or even a week or more) for updates to be available on `F-Droid` once an update has been released on `GitHub`. The `F-Droid` releases are built and published by `F-Droid` once they [detect](https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/com.termux.yml) a new `GitHub` release. The Termux maintainers **do not** have any control over the building and publishing of the Termux apps on `F-Droid`. Moreover, the Termux maintainers also do not have access to the APK signing keys of `F-Droid` releases, so we cannot release an APK ourselves on `GitHub` that would be compatible with `F-Droid` releases.

The `F-Droid` app often may not notify you of updates and you will manually have to do a pull down swipe action in the `Updates` tab of the app for it to check updates. Make sure battery optimizations are disabled for the app, check https://dontkillmyapp.com/ for details on how to do that.

Only a universal APK is released, which will work on all supported architectures. The APK and bootstrap installation size will be `~180MB`. `F-Droid` does [not support](https://github.com/termux/termux-app/pull/1904) architecture specific APKs.

### GitHub

Termux application can be obtained on `GitHub` either from [`GitHub Releases`](https://github.com/termux/termux-app/releases) for version `>= 0.118.0` or from [`GitHub Build Action`](https://github.com/termux/termux-app/actions/workflows/debug_build.yml?query=branch%3Amaster+event%3Apush) workflows. **For android `>= 7`, only install `apt-android-7` variants. For android `5` and `6`, only install `apt-android-5` variants.**

The APKs for `GitHub Releases` will be listed under `Assets` drop-down of a release. These are automatically attached when a new version is released.

The APKs for `GitHub Build` action workflows will be listed under `Artifacts` section of a workflow run. These are created for each commit/push done to the repository and can be used by users who don't want to wait for releases and want to try out the latest features immediately or want to test their pull requests. Note that for action workflows, you need to be [**logged into a `GitHub` account**](https://github.com/login) for the `Artifacts` links to be enabled/clickable. If you are using the [`GitHub` app](https://github.com/mobile), then make sure to open workflow link in a browser like Chrome or Firefox that has your GitHub account logged in since the in-app browser may not be logged in.

The APKs for both of these are [`debuggable`](https://developer.android.com/studio/debug) and are compatible with each other but they are not compatible with other sources.

Both universal and architecture specific APKs are released. The APK and bootstrap installation size will be `~180MB` if using universal and `~120MB` if using architecture specific. Check [here](https://github.com/termux/termux-app/issues/2153) for details.

**Security warning**: APK files on GitHub are signed with a test key that has been [shared with community](https://github.com/termux/termux-app/blob/master/app/testkey_untrusted.jks). This IS NOT an official developer key and everyone can use it to generate releases for own testing. Be very careful when using Termux GitHub builds obtained elsewhere except https://github.com/termux/termux-app. Everyone is able to use it to forge a malicious Termux update installable over the GitHub build. Think twice about installing Termux builds distributed via Telegram or other social media. If your device get caught by malware, we will not be able to help you.

The [test key](https://github.com/termux/termux-app/blob/master/app/testkey_untrusted.jks) shall not be used to impersonate @termux and can't be used for this anyway. This key is not trusted by us and it is quite easy to detect its use in user generated content.

<details>
<summary>Keystore information</summary>

```
Alias name: alias
Creation date: Oct 4, 2019
Entry type: PrivateKeyEntry
Certificate chain length: 1
Certificate[1]:
Owner: CN=APK Signer, OU=Earth, O=Earth
Issuer: CN=APK Signer, OU=Earth, O=Earth
Serial number: 29be297b
Valid from: Wed Sep 04 02:03:24 EEST 2019 until: Tue Oct 26 02:03:24 EEST 2049
Certificate fingerprints:
         SHA1: 51:79:55:EA:BF:69:FC:05:7C:41:C7:D3:79:DB:BC:EF:20:AD:85:F2
         SHA256: B6:DA:01:48:0E:EF:D5:FB:F2:CD:37:71:B8:D1:02:1E:C7:91:30:4B:DD:6C:4B:F4:1D:3F:AA:BA:D4:8E:E5:E1
Signature algorithm name: SHA1withRSA (disabled)
Subject Public Key Algorithm: 2048-bit RSA key
Version: 3
```

</details>

### Google Play Store **(Experimental branch)**

There is currently a build of Termux available on Google Play for Android 11+ devices, with extensive adjustments in order to pass policy requirements there. This is under development and has missing functionality and bugs (see [here](https://github.com/termux-play-store/) for status updates) compared to the stable F-Droid build, which is why most users who can should still use F-Droid or GitHub build as mentioned above.

Currently, Google Play will try to update installations away from F-Droid ones. Updating will still fail as [sharedUserId](https://developer.android.com/guide/topics/manifest/manifest-element#uid) has been removed. A planned 0.118.1 F-Droid release will fix this by setting a higher version code than used for the PlayStore app. Meanwhile, to prevent Google Play from attempting to download and then fail to install the Google Play releases over existing installations, you can open the Termux apps pages on Google Play and then click on the 3 dots options button in the top right and then disable the Enable auto update toggle. However, the Termux apps updates will still show in the PlayStore app updates list.

If you want to help out with testing the Google Play build (or cannot install Termux from other sources), be aware that it's built from a separate repository (https://github.com/termux-play-store/) - be sure to report issues [there](https://github.com/termux-play-store/termux-issues/issues/new/choose), as any issues encountered might very well be specific to that repository.

## Uninstallation

Uninstallation may be required if a user doesn't want Termux installed in their device anymore or is switching to a different [install source](#installation). You may also want to consider [Backing up Termux](https://wiki.termux.com/wiki/Backing_up_Termux) before the uninstallation.

To uninstall Termux completely, you must uninstall **any and all existing Termux or its plugin app APKs** listed in [Termux App and Plugins](#termux-app-and-plugins).

Go to `Android Settings` -> `Applications` and then look for those apps. You can also use the search feature if it’s available on your device and search `termux` in the applications list.

Even if you think you have not installed any of the plugins, it's strongly suggested to go through the application list in Android settings and double-check.
---



## Important Links

### Community
All community links are available [here](https://wiki.termux.com/wiki/Community).

The main ones are the following.

- [Termux Reddit community](https://reddit.com/r/termux)
- [Termux User Matrix Channel](https://matrix.to/#/#termux_termux:gitter.im) ([Gitter](https://gitter.im/termux/termux))
- [Termux Dev Matrix Channel](https://matrix.to/#/#termux_dev:gitter.im) ([Gitter](https://gitter.im/termux/dev))
- [Termux X (Twitter)](https://twitter.com/termuxdevs)
- [Termux Support Email](mailto:support@termux.dev)

### Wikis

- [Termux Wiki](https://wiki.termux.com/wiki/)
- [Termux App Wiki](https://github.com/termux/termux-app/wiki)
- [Termux Packages Wiki](https://github.com/termux/termux-packages/wiki)

### Miscellaneous
- [FAQ](https://wiki.termux.com/wiki/FAQ)
- [Termux File System Layout](https://github.com/termux/termux-packages/wiki/Termux-file-system-layout)
- [Differences From Linux](https://wiki.termux.com/wiki/Differences_from_Linux)
- [Package Management](https://wiki.termux.com/wiki/Package_Management)
- [Remote Access](https://wiki.termux.com/wiki/Remote_Access)
- [Backing up Termux](https://wiki.termux.com/wiki/Backing_up_Termux)
- [Terminal Settings](https://wiki.termux.com/wiki/Terminal_Settings)
- [Touch Keyboard](https://wiki.termux.com/wiki/Touch_Keyboard)
- [Android Storage and Sharing Data with Other Apps](https://wiki.termux.com/wiki/Internal_and_external_storage)
- [Android APIs](https://wiki.termux.com/wiki/Termux:API)
- [Moved Termux Packages Hosting From Bintray to IPFS](https://github.com/termux/termux-packages/issues/6348)
- [Running Commands in Termux From Other Apps via `RUN_COMMAND` intent](https://github.com/termux/termux-app/wiki/RUN_COMMAND-Intent)
- [Termux and Android 10](https://github.com/termux/termux-packages/wiki/Termux-and-Android-10)


### Terminal

<details>
<summary></summary>

### Terminal resources

- [XTerm control sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)
- [vt100.net](https://vt100.net/)
- [Terminal codes (ANSI and terminfo equivalents)](https://wiki.bash-hackers.org/scripting/terminalcodes)

### Terminal emulators

- VTE (libvte): Terminal emulator widget for GTK+, mainly used in gnome-terminal. [Source](https://github.com/GNOME/vte), [Open Issues](https://bugzilla.gnome.org/buglist.cgi?quicksearch=product%3A%22vte%22+), and [All (including closed) issues](https://bugzilla.gnome.org/buglist.cgi?bug_status=RESOLVED&bug_status=VERIFIED&chfield=resolution&chfieldfrom=-2000d&chfieldvalue=FIXED&product=vte&resolution=FIXED).

- iTerm 2: OS X terminal application. [Source](https://github.com/gnachman/iTerm2), [Issues](https://gitlab.com/gnachman/iterm2/issues) and [Documentation](https://iterm2.com/documentation.html) (which includes [iTerm2 proprietary escape codes](https://iterm2.com/documentation-escape-codes.html)).

- Konsole: KDE terminal application. [Source](https://projects.kde.org/projects/kde/applications/konsole/repository), in particular [tests](https://projects.kde.org/projects/kde/applications/konsole/repository/revisions/master/show/tests), [Bugs](https://bugs.kde.org/buglist.cgi?bug_severity=critical&bug_severity=grave&bug_severity=major&bug_severity=crash&bug_severity=normal&bug_severity=minor&bug_status=UNCONFIRMED&bug_status=NEW&bug_status=ASSIGNED&bug_status=REOPENED&product=konsole) and [Wishes](https://bugs.kde.org/buglist.cgi?bug_severity=wishlist&bug_status=UNCONFIRMED&bug_status=NEW&bug_status=ASSIGNED&bug_status=REOPENED&product=konsole).

- hterm: JavaScript terminal implementation from Chromium. [Source](https://github.com/chromium/hterm), including [tests](https://github.com/chromium/hterm/blob/master/js/hterm_vt_tests.js), and [Google group](https://groups.google.com/a/chromium.org/forum/#!forum/chromium-hterm).

- xterm: The grandfather of terminal emulators. [Source](https://invisible-island.net/datafiles/release/xterm.tar.gz).

- Connectbot: Android SSH client. [Source](https://github.com/connectbot/connectbot)

- Android Terminal Emulator: Android terminal app which Termux terminal handling is based on. Inactive. [Source](https://github.com/jackpal/Android-Terminal-Emulator).
</details>

---



### Debugging

You can help debug problems of the `Termux` app and its plugins by setting appropriate `logcat` `Log Level` in `Termux` app settings -> `<APP_NAME>` -> `Debugging` -> `Log Level` (Requires `Termux` app version `>= 0.118.0`). The `Log Level` defaults to `Normal` and log level `Verbose` currently logs additional information. Its best to revert log level to `Normal` after you have finished debugging since private data may otherwise be passed to `logcat` during normal operation and moreover, additional logging increases execution time.

The plugin apps **do not execute the commands themselves** but send execution intents to `Termux` app, which has its own log level which can be set in `Termux` app settings -> `Termux` -> `Debugging` -> `Log Level`. So you must set log level for both `Termux` and the respective plugin app settings to get all the info.

Once log levels have been set, you can run the `logcat` command in `Termux` app terminal to view the logs in realtime (`Ctrl+c` to stop) or use `logcat -d > logcat.txt` to take a dump of the log. You can also view the logs from a PC over `ADB`. For more information, check official android `logcat` guide [here](https://developer.android.com/studio/command-line/logcat).

Moreover, users can generate termux files `stat` info and `logcat` dump automatically too with terminal's long hold options menu `More` -> `Report Issue` option and selecting `YES` in the prompt shown to add debug info. This can be helpful for reporting and debugging other issues. If the report generated is too large, then `Save To File` option in context menu (3 dots on top right) of `ReportActivity` can be used and the file viewed/shared instead.

Users must post complete report (optionally without sensitive info) when reporting issues. Issues opened with **(partial) screenshots of error reports** instead of text will likely be automatically closed/deleted.

##### Log Levels

- `Off` - Log nothing.
- `Normal` - Start logging error, warn and info messages and stacktraces.
- `Debug` - Start logging debug messages.
- `Verbose` - Start logging verbose messages.
---



## For Maintainers and Contributors

The [termux-shared](termux-shared) library was added in [`v0.109`](https://github.com/termux/termux-app/releases/tag/v0.109). It defines shared constants and utils of the Termux app and its plugins. It was created to allow for the removal of all hardcoded paths in the Termux app. Some of the termux plugins are using this as well and rest will in future. If you are contributing code that is using a constant or a util that may be shared, then define it in `termux-shared` library if it currently doesn't exist and reference it from there. Update the relevant changelogs as well. Pull requests using hardcoded values **will/should not** be accepted. Termux app and plugin specific classes must be added under `com.termux.shared.termux` package and general classes outside it. The [`termux-shared` `LICENSE`](termux-shared/LICENSE.md) must also be checked and updated if necessary when contributing code. The licenses of any external library or code must be honoured.

The main Termux constants are defined by [`TermuxConstants`](https://github.com/termux/termux-app/blob/master/termux-shared/src/main/java/com/termux/shared/termux/TermuxConstants.java) class. It also contains information on how to fork Termux or build it with your own package name. Changing the package name will require building the bootstrap zip packages and other packages with the new `$PREFIX`, check [Building Packages](https://github.com/termux/termux-packages/wiki/Building-packages) for more info.

Check [Termux Libraries](https://github.com/termux/termux-app/wiki/Termux-Libraries) for how to import termux libraries in plugin apps and [Forking and Local Development](https://github.com/termux/termux-app/wiki/Termux-Libraries#forking-and-local-development) for how to update termux libraries for plugins.

The `versionName` in `build.gradle` files of Termux and its plugin apps must follow the [semantic version `2.0.0` spec](https://semver.org/spec/v2.0.0.html) in the format `major.minor.patch(-prerelease)(+buildmetadata)`. When bumping `versionName` in `build.gradle` files and when creating a tag for new releases on GitHub, make sure to include the patch number as well, like `v0.1.0` instead of just `v0.1`. The `build.gradle` files and `attach_debug_apks_to_release` workflow validates the version as well and the build/attachment will fail if `versionName` does not follow the spec.

### Commit Messages Guidelines

Commit messages **must** use the [Conventional Commits](https://www.conventionalcommits.org) spec so that chagelogs as per the [Keep a Changelog](https://github.com/olivierlacan/keep-a-changelog) spec can automatically be generated by the [`create-conventional-changelog`](https://github.com/termux/create-conventional-changelog) script, check its repo for further details on the spec. **The first letter for `type` and `description` must be capital and description should be in the present tense.** The space after the colon `:` is necessary. For a breaking change, add an exclamation mark `!` before the colon `:`, so that it is highlighted in the chagelog automatically.

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Only the `types` listed below must be used exactly as they are used in the changelog headings.** For example, `Added: Add foo`, `Added|Fixed: Add foo and fix bar`, `Changed!: Change baz as a breaking change`, etc. You can optionally add a scope as well, like `Fixed(terminal): Fix some bug`. **Do not use anything else as type, like `add` instead of `Added`, etc.**

- **Added** for new features.
- **Changed** for changes in existing functionality.
- **Deprecated** for soon-to-be removed features.
- **Removed** for now removed features.
- **Fixed** for any bug fixes.
- **Security** in case of vulnerabilities.
---



## Forking

- Check [`TermuxConstants`](https://github.com/termux/termux-app/blob/master/termux-shared/src/main/java/com/termux/shared/termux/TermuxConstants.java) javadocs for instructions on what changes to make in the app to change package name.
- You also need to recompile bootstrap zip for the new package name. Check [building bootstrap](https://github.com/termux/termux-packages/wiki/For-maintainers#build-bootstrap-archives), [here](https://github.com/termux/termux-app/issues/1983) and [here](https://github.com/termux/termux-app/issues/2081#issuecomment-865280111).
- Currently, not all plugins use `TermuxConstants` from `termux-shared` library and have hardcoded `com.termux` values and will need to be manually patched.
- If forking termux plugins, check [Forking and Local Development](https://github.com/termux/termux-app/wiki/Termux-Libraries#forking-and-local-development) for info on how to use termux libraries for plugins.
---



## Sponsors and Funders

[<img alt="GitHub Accelerator" width="25%" src="site/assets/sponsors/github.png" />](https://github.com)  
*[GitHub Accelerator](https://github.com/accelerator) ([1](https://github.blog/2023-04-12-github-accelerator-our-first-cohort-and-whats-next))*

&nbsp;

[<img alt="GitHub Secure Open Source Fund" width="25%" src="site/assets/sponsors/github.png" />](https://github.com)  
*[GitHub Secure Open Source Fund](https://resources.github.com/github-secure-open-source-fund) ([1](https://github.blog/open-source/maintainers/securing-the-supply-chain-at-scale-starting-with-71-important-open-source-projects), [2](https://termux.dev/en/posts/general/2025/08/11/termux-selected-for-github-secure-open-source-fund-session-2.html))*

&nbsp;

[<img alt="NLnet NGI Mobifree" width="25%" src="site/assets/sponsors/nlnet-ngi-mobifree.png" />](https://nlnet.nl/mobifree)  
*[NLnet NGI Mobifree](https://nlnet.nl/mobifree) ([1](https://nlnet.nl/news/2024/20241111-NGI-Mobifree-grants.html), [2](https://termux.dev/en/posts/general/2024/11/11/termux-selected-for-nlnet-ngi-mobifree-grant.html))*

&nbsp;

[<img alt="Cloudflare" width="25%" src="site/assets/sponsors/cloudflare.png" />](https://www.cloudflare.com)  
*[Cloudflare](https://www.cloudflare.com) ([1](https://packages-cf.termux.dev))*

&nbsp;

[<img alt="Warp" width="25%" src="https://github.com/warpdotdev/brand-assets/blob/640dffd347439bbcb535321ab36b7281cf4446c0/Github/Sponsor/Warp-Github-LG-03.png" />](https://www.warp.dev/?utm_source=github&utm_medium=readme&utm_campaign=termux)  
[*Warp, built for coding with multiple AI agents*](https://www.warp.dev/?utm_source=github&utm_medium=readme&utm_campaign=termux)

---

## Acknowledgments and Attribution

**For a complete list of contributors and detailed attribution information, please see [CONTRIBUTORS.md](CONTRIBUTORS.md).**

### Upstream Project Acknowledgment

This project is a fork of the **Termux** project, originally created and maintained by the Termux development team. We are deeply grateful to all the original contributors who have made Termux what it is today. Their work forms the foundation of this fork.

**Original Termux Project:**
- Repository: [https://github.com/termux/termux-app](https://github.com/termux/termux-app)
- Website: [https://termux.com](https://termux.com)
- License: GPLv3 (with specified exceptions)

### Component Attributions

This project incorporates code from multiple sources, each with their own licenses and contributors:

#### 1. Termux Core Application
- **Copyright**: © Termux developers and contributors
- **License**: GPLv3 only
- **Source**: [termux/termux-app](https://github.com/termux/termux-app)
- **Attribution**: All core functionality, UI, and terminal integration

#### 2. Terminal Emulator for Android
- **Copyright**: © Jack Palevich and contributors
- **License**: Apache 2.0
- **Source**: [jackpal/Android-Terminal-Emulator](https://github.com/jackpal/Android-Terminal-Emulator)
- **Attribution**: Terminal emulation engine used in `terminal-view` and `terminal-emulator` libraries
- **License Text**: [Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0)

#### 3. Termux-Shared Library
- **Copyright**: © Termux developers and contributors
- **License**: MIT (with GPLv3 exceptions for specific directories)
- **Details**: See [termux-shared/LICENSE.md](termux-shared/LICENSE.md)
- **Exceptions**:
  - GPLv3 for `src/main/java/com/termux/shared/termux/*`
  - GPLv2 with Classpath exception for filesystem components derived from Android libcore/ojluni
  - Apache 2.0 for StreamGobbler derived from libsuperuser

#### 4. Android Open Source Project (AOSP) Components
- **Copyright**: © The Android Open Source Project
- **License**: GPLv2 with Classpath Exception
- **Source**: [Android Platform libcore/ojluni](https://cs.android.com/android/platform/superproject/+/android-11.0.0_r3:libcore/ojluni/)
- **Attribution**: Filesystem utilities in `termux-shared/src/main/java/com/termux/shared/file/filesystem/`

#### 5. libsuperuser
- **Copyright**: © Chainfire
- **License**: Apache 2.0
- **Source**: [Chainfire/libsuperuser](https://github.com/Chainfire/libsuperuser)
- **Attribution**: StreamGobbler implementation in `termux-shared/src/main/java/com/termux/shared/shell/StreamGobbler.java`

### Contributors

We acknowledge and thank:

1. **Original Termux Team and All Contributors** - For creating and maintaining the original Termux application
2. **Jack Palevich** - For the Android Terminal Emulator that serves as the foundation for terminal functionality
3. **Chainfire** - For libsuperuser components
4. **The Android Open Source Project** - For filesystem utilities
5. **All community contributors** - Everyone who has contributed code, bug reports, documentation, translations, and support to the Termux ecosystem

### Full License Texts

For complete license texts and legal information:
- GPLv3: [https://www.gnu.org/licenses/gpl-3.0.html](https://www.gnu.org/licenses/gpl-3.0.html)
- Apache 2.0: [https://www.apache.org/licenses/LICENSE-2.0](https://www.apache.org/licenses/LICENSE-2.0)
- MIT: [https://opensource.org/licenses/MIT](https://opensource.org/licenses/MIT)
- GPLv2 with Classpath Exception: [https://openjdk.java.net/legal/gplv2+ce.html](https://openjdk.java.net/legal/gplv2+ce.html)

### Copyright Notice

This fork maintains all original copyright notices and attributions. Any modifications made in this fork are:
- **Copyright**: © instituto-Rafael and RafaCodePhi contributors
- **License**: GPLv3 (matching the upstream license)

### Legal Compliance

This project complies with:
- The GNU General Public License v3.0
- The Apache License 2.0 for applicable components
- The MIT License for applicable components
- International copyright law and intellectual property regulations
- All license requirements including attribution, notice preservation, and copyleft provisions

Every contribution, no matter how small, is significant and acknowledged. Even a single character or punctuation mark change is attributed to its contributor, as required by software licensing best practices and copyright law.

### Trademark Notice

"Termux" is a trademark of the original Termux project. This fork is not officially endorsed by or affiliated with the original Termux project, though it maintains full compliance with the GPLv3 license under which Termux is released.


## Security and release policy (RAFCODEΦ)

- Package name oficial e único: `com.termux.rafacodephi`.
- Keystores/chaves de release não devem ser versionados; use apenas variáveis de ambiente para signing oficial.
- Trilha interna unsigned é somente para validação técnica, nunca para release oficial.
- `TERMUX_BOOTSTRAP_VALIDATION_MODE=upstream-debug-compat` é bloqueado nos scripts de release.
- Hashes de bootstrap BLAKE3 e SHA256 são gerados por `scripts/prepare_bootstrap_env.sh`.

ABIs validadas na trilha de build local: `armeabi-v7a`, `arm64-v8a` e `x86_64`.

## Manifesto: Parábola do Zero e do Um

> O sábio não chamou o vazio de inútil, nem chamou o cheio de verdade. Ele colocou os dois na balança da coerência.

Neste fork, tratamos linguagem, build e execução como estados coerentes de um mesmo sistema:

- **0 = campo de possibilidade** (silêncio útil, estado ainda não provado).
- **1 = manifestação validada** (ação comprovada, estado executável).
- **Ruído = diferença entre esperado e vivido** (fronteira de ajuste fino).
- **Erro = quebra de aliança do sistema** (contrato rompido entre camadas).

Princípios operacionais do manifesto:

1. Não confundir ausência com inutilidade e presença com verdade automática.
2. Medir transições entre estado potencial e estado validado com provas reprodutíveis.
3. Preservar coerência entre Gradle, CMake, NDK, JNI, CI e artefatos.
4. Tratar rollback como parte legítima da engenharia de confiabilidade.
5. Manter o caminho oficial de release íntegro, com trilhas explícitas para validação interna.

Mapeamento semântico adotado neste projeto:

```text
0 = campo de possibilidade
1 = manifestação validada
Arché = origem da estrutura
Elohim = inteligência ordenadora
Qudra = potência de execução
Tao = caminho da transição
Zen = silêncio que não falsifica
Torá = ordem pela palavra
Alcorão = comando que faz ser
RAFAELIA = tentativa de medir a passagem entre possibilidade, estado e prova
```

Este manifesto define o compromisso do repositório com coerência estrutural, validação técnica e evolução semântica responsável.


## Certification and audit claim notice

This repository does not claim ISO certification, formal ISO compliance, or accredited external audit status. Any ISO/IEC references are internal checklist references or methodological alignment notes only. Certification requires an external accredited audit process and is outside the scope of this repository.

Este repositório não declara certificação formal baseada em ISO, conformidade ISO formal nem auditoria externa acreditada. Qualquer referência a ISO/IEC é apenas checklist interno, referência metodológica ou alinhamento preliminar de boas práticas. Certificação exige processo externo acreditado e está fora do escopo deste repositório.

### Audit/benchmark/runtime trail
- `docs/AUDIT_CLAIMS_POLICY.md`
- `reports/vectra_grade_benchmarks.md`
- `reports/device_runtime_smoke.md`
- `reports/rmr_equivalence.md`
- CI validação não equivale a validação em device real.
- Benchmark definido não equivale a benchmark medido.

## Estado do target bootstrap_rafaelia

- O target atual deste núcleo é **Termux/userland** (processo normal em userspace).
- Este estágio **não** é freestanding com `_raf_start` como entrypoint final de produto.
- Este estágio **não** é uma biblioteca `.so` JNI para consumo Android app.
- Próximo target planejado: trilhas dedicadas para **freestanding** e **`librmr.so`**.

### Governança de promoção `Arme/`

- `Arme/Add/` é staging de ingestão e **não** entra na trilha oficial de build/release sem promoção.
- Promoções devem usar `scripts/promote_arme_module.sh` para validar manifesto, exigir teste mínimo de equivalência C/ASM e registrar auditoria em `Arme/reports/promotion_audit.log`.
- O CI aplica bloqueio para novos `.c/.h/.S` em `Arme/Add/` sem entrada correspondente em `Arme/manifest.json`.

## Linux/PC user-space contract (Rafaelia)

Camadas separadas e obrigatórias:

1. **Termux bootstrap**: ZIPs por ABI (`bootstrap-aarch64.zip`, `bootstrap-arm.zip`, `bootstrap-i686.zip`, `bootstrap-x86_64.zip`) com hash SHA256/BLAKE3 para contrato de release.
2. **Linux rootfs em PRoot**: distro real (padrão Debian minimal) instalada em `$PREFIX/var/lib/rafaelia-linux/debian/rootfs`.
3. **VM/Emulação (QEMU/Vectras)**: camada opcional acima do user-space Linux; não substitui bootstrap nem rootfs.

### Instalar Linux Debian minimal (CLI primeiro)

```bash
./install-rafaelia-linux.sh
./start-rafaelia-linux.sh
```

O instalador:
- baixa rootfs oficial do `proot-distro` por ABI,
- valida SHA256 antes da extração,
- gera `resolv.conf` no rootfs,
- cria launcher único com binds de `/dev`, `/proc`, `/sys`, `/tmp`, `/sdcard` e home persistente.

Validação inicial recomendada (sem desktop):

```bash
./start-rafaelia-linux.sh -lc 'cat /etc/os-release'
./start-rafaelia-linux.sh -lc 'apt update'
./start-rafaelia-linux.sh -lc 'python3 --version'
./start-rafaelia-linux.sh -lc 'gcc --version'
```
