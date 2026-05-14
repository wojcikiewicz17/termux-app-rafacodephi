# Debug Bootstrap Local Build Report

- Date (UTC): 2026-05-14 02:13:58
- Repo: termux-app-rafacodephi
- Mode: RAF_BOOTSTRAP_SOURCE=local

## Execution

### Command
```bash
bash scripts/setup_android_toolchain.sh
```
- Status: **PASS**
- Output:
```text
📦 Android toolchain source of truth: gradle.properties
compileSdkVersion=35
targetSdkVersion=34
ndkVersion=26.3.11579264
buildToolsVersion=35.0.0
ℹ️ Preserving existing sdk.dir in local.properties
```

### Command
```bash
bash scripts/verify_bootstrap_contract.sh --prepare-dev
```
- Status: **PASS**
- Output:
```text
[bootstrap-contract] Free space check OK: 25265MB >= 1024MB
RAFCODEPHI bootstraps generated for package=com.termux.rafacodephi page_size=16384
[bootstrap-contract] Free space check OK: 25265MB >= 1024MB
[bootstrap-contract] Zip validation OK: app/src/main/cpp/bootstrap-aarch64.zip
[bootstrap-contract] Zip validation OK: app/src/main/cpp/bootstrap-arm.zip
[bootstrap-contract] Zip validation OK: app/src/main/cpp/bootstrap-i686.zip
[bootstrap-contract] Zip validation OK: app/src/main/cpp/bootstrap-x86_64.zip
metadata OK for RAFCODEPHI local bootstraps
[bootstrap-contract] BOOTSTRAP_INFO metadata OK
SHA256 bootstrap-aarch64.zip 0314cb70c83279d1a272b102f1ebc0bc80ff6a9355a1baeef9a4fcd254459bc3
SHA256 bootstrap-arm.zip 6fad47495a7d71764dca06335fdf1a53231d5fa778607d51df8e9dda46da4ac9
SHA256 bootstrap-i686.zip a2aca1d570b88f06e11abc74324db37ca6761980dc4fac5170e1dee6c25f1473
SHA256 bootstrap-x86_64.zip b1d9499975a609bb5f7c4ae2020ea1237f5782c1e5f5b881287bb9b28bd1d61c
[bootstrap-contract] b3sum unavailable; BLAKE3 skipped (SHA256 emitted).
[bootstrap-contract] PREFIX/TERMUX_PREFIX not set; runtime check skipped (build mode).
```

### Command
```bash
RAF_BOOTSTRAP_SOURCE=local ./gradlew :app:ensureBootstrapArchives --no-daemon
```
- Status: **PASS**
- Output:
```text
To honour the JVM settings for this build a single-use Daemon process will be forked. For more on this, please refer to https://docs.gradle.org/8.14.3/userguide/gradle_daemon.html#sec:disabling_the_daemon in the Gradle documentation.
Daemon will be stopped at the end of the build 
Configuration on demand is an incubating feature.

> Configure project :app
Release signing is disabled. assembleRelease will generate an unsigned artifact.

> Task :app:buildDeveloperBootstraps
RAFCODEPHI bootstraps generated for package=com.termux.rafacodephi page_size=16384

> Task :app:validateBootstrapBlake3Config
Missing TERMUX_BOOTSTRAP_BLAKE3_* for architectures: AARCH64, ARM, I686, X86_64. Set TERMUX_BOOTSTRAP_BLAKE3_AARCH64/ARM/I686/X86_64 before release builds. Debug builds are allowed but are not BOOTSTRAP_RUNTIME_READY.

> Task :app:downloadBootstraps
> Task :app:verifyBootstrapZipsPresent
> Task :app:ensureBootstrapArchives

[Incubating] Problems report is available at: file:///workspace/termux-app-rafacodephi/build/reports/problems/problems-report.html

Deprecated Gradle features were used in this build, making it incompatible with Gradle 9.0.

You can use '--warning-mode all' to show the individual deprecation warnings and determine if they come from your own scripts or plugins.

For more on this, please refer to https://docs.gradle.org/8.14.3/userguide/command_line_interface.html#sec:command_line_warnings in the Gradle documentation.

BUILD SUCCESSFUL in 20s
4 actionable tasks: 4 executed
```

### Command
```bash
RAF_BOOTSTRAP_SOURCE=local ./gradlew assembleDebug --no-daemon
```
- Status: **PASS**
- Output:
```text
To honour the JVM settings for this build a single-use Daemon process will be forked. For more on this, please refer to https://docs.gradle.org/8.14.3/userguide/gradle_daemon.html#sec:disabling_the_daemon in the Gradle documentation.
Daemon will be stopped at the end of the build 
Configuration on demand is an incubating feature.

> Configure project :app
Release signing is disabled. assembleRelease will generate an unsigned artifact.

> Task :rafaelia:preBuild UP-TO-DATE
> Task :rmr:preBuild UP-TO-DATE
> Task :rafaelia:preDebugBuild UP-TO-DATE
> Task :rmr:preDebugBuild UP-TO-DATE
> Task :rafaelia:writeDebugAarMetadata UP-TO-DATE
> Task :terminal-emulator:preBuild UP-TO-DATE
> Task :rmr:writeDebugAarMetadata UP-TO-DATE
> Task :terminal-view:preBuild UP-TO-DATE
> Task :terminal-view:preDebugBuild UP-TO-DATE
> Task :terminal-emulator:preDebugBuild UP-TO-DATE
> Task :terminal-view:writeDebugAarMetadata UP-TO-DATE
> Task :termux-shared:preBuild UP-TO-DATE
> Task :termux-shared:preDebugBuild UP-TO-DATE
> Task :terminal-emulator:writeDebugAarMetadata UP-TO-DATE
> Task :termux-shared:writeDebugAarMetadata UP-TO-DATE
> Task :rafaelia:processDebugNavigationResources UP-TO-DATE
> Task :rmr:processDebugNavigationResources UP-TO-DATE
> Task :terminal-view:processDebugNavigationResources UP-TO-DATE
> Task :terminal-emulator:processDebugNavigationResources UP-TO-DATE
> Task :termux-shared:processDebugNavigationResources UP-TO-DATE
> Task :rafaelia:generateDebugResValues UP-TO-DATE
> Task :rmr:generateDebugResValues UP-TO-DATE
> Task :rafaelia:generateDebugResources UP-TO-DATE
> Task :rmr:generateDebugResources UP-TO-DATE
> Task :rafaelia:packageDebugResources UP-TO-DATE
> Task :rmr:packageDebugResources UP-TO-DATE
> Task :terminal-emulator:generateDebugResValues UP-TO-DATE
> Task :terminal-view:generateDebugResValues UP-TO-DATE
> Task :terminal-emulator:generateDebugResources UP-TO-DATE
> Task :terminal-view:generateDebugResources UP-TO-DATE
> Task :terminal-emulator:packageDebugResources UP-TO-DATE
> Task :terminal-view:packageDebugResources UP-TO-DATE
> Task :termux-shared:generateDebugResValues UP-TO-DATE
> Task :rafaelia:extractDeepLinksDebug UP-TO-DATE
> Task :termux-shared:generateDebugResources UP-TO-DATE
> Task :termux-shared:packageDebugResources UP-TO-DATE
> Task :rafaelia:processDebugManifest UP-TO-DATE
> Task :rmr:extractDeepLinksDebug UP-TO-DATE
> Task :rmr:processDebugManifest UP-TO-DATE
> Task :terminal-emulator:extractDeepLinksDebug UP-TO-DATE
> Task :terminal-emulator:processDebugManifest UP-TO-DATE
> Task :terminal-view:extractDeepLinksDebug UP-TO-DATE
> Task :terminal-view:processDebugManifest UP-TO-DATE
> Task :termux-shared:extractDeepLinksDebug UP-TO-DATE
> Task :termux-shared:processDebugManifest UP-TO-DATE
> Task :rafaelia:compileDebugLibraryResources UP-TO-DATE
> Task :rafaelia:parseDebugLocalResources UP-TO-DATE
> Task :rafaelia:generateDebugRFile UP-TO-DATE
> Task :rmr:compileDebugLibraryResources UP-TO-DATE
> Task :rmr:parseDebugLocalResources UP-TO-DATE
> Task :rmr:generateDebugRFile UP-TO-DATE
> Task :terminal-emulator:compileDebugLibraryResources UP-TO-DATE
> Task :terminal-emulator:parseDebugLocalResources UP-TO-DATE
> Task :terminal-emulator:generateDebugRFile UP-TO-DATE
> Task :terminal-view:compileDebugLibraryResources UP-TO-DATE
> Task :terminal-view:parseDebugLocalResources UP-TO-DATE
> Task :terminal-view:generateDebugRFile UP-TO-DATE
> Task :termux-shared:compileDebugLibraryResources UP-TO-DATE
> Task :termux-shared:parseDebugLocalResources UP-TO-DATE
> Task :termux-shared:generateDebugRFile UP-TO-DATE
> Task :rafaelia:javaPreCompileDebug UP-TO-DATE

> Task :app:buildDeveloperBootstraps
RAFCODEPHI bootstraps generated for package=com.termux.rafacodephi page_size=16384

> Task :rafaelia:compileDebugJavaWithJavac UP-TO-DATE
> Task :rafaelia:bundleLibCompileToJarDebug UP-TO-DATE
> Task :rmr:javaPreCompileDebug UP-TO-DATE
> Task :rmr:compileDebugJavaWithJavac UP-TO-DATE
> Task :rmr:bundleLibCompileToJarDebug UP-TO-DATE
> Task :terminal-emulator:javaPreCompileDebug UP-TO-DATE
> Task :terminal-emulator:compileDebugJavaWithJavac UP-TO-DATE
> Task :terminal-emulator:bundleLibCompileToJarDebug UP-TO-DATE
> Task :terminal-view:javaPreCompileDebug UP-TO-DATE
> Task :terminal-view:compileDebugJavaWithJavac UP-TO-DATE
> Task :terminal-view:bundleLibCompileToJarDebug UP-TO-DATE
> Task :termux-shared:javaPreCompileDebug UP-TO-DATE

> Task :app:validateBootstrapBlake3Config
Missing TERMUX_BOOTSTRAP_BLAKE3_* for architectures: AARCH64, ARM, I686, X86_64. Set TERMUX_BOOTSTRAP_BLAKE3_AARCH64/ARM/I686/X86_64 before release builds. Debug builds are allowed but are not BOOTSTRAP_RUNTIME_READY.

> Task :app:downloadBootstraps
> Task :app:verifyBootstrapZipsPresent
> Task :app:ensureBootstrapArchives
> Task :app:preBuild UP-TO-DATE
> Task :app:preDebugBuild
> Task :app:mergeDebugNativeDebugMetadata NO-SOURCE
> Task :app:generateDebugBuildConfig UP-TO-DATE
> Task :app:javaPreCompileDebug UP-TO-DATE
> Task :app:checkDebugAarMetadata UP-TO-DATE
> Task :rafaelia:mergeDebugShaders UP-TO-DATE
> Task :termux-shared:compileDebugJavaWithJavac UP-TO-DATE
> Task :rafaelia:compileDebugShaders NO-SOURCE
> Task :rafaelia:generateDebugAssets UP-TO-DATE
> Task :termux-shared:bundleLibCompileToJarDebug UP-TO-DATE
> Task :rafaelia:mergeDebugAssets UP-TO-DATE
> Task :terminal-emulator:mergeDebugShaders UP-TO-DATE
> Task :rmr:mergeDebugShaders UP-TO-DATE
> Task :rmr:compileDebugShaders NO-SOURCE
> Task :rmr:generateDebugAssets UP-TO-DATE
> Task :terminal-emulator:compileDebugShaders NO-SOURCE
> Task :terminal-emulator:generateDebugAssets UP-TO-DATE
> Task :rmr:mergeDebugAssets UP-TO-DATE
> Task :terminal-emulator:mergeDebugAssets UP-TO-DATE
> Task :terminal-view:mergeDebugShaders UP-TO-DATE
> Task :termux-shared:mergeDebugShaders UP-TO-DATE
> Task :terminal-view:compileDebugShaders NO-SOURCE
> Task :terminal-view:generateDebugAssets UP-TO-DATE
> Task :termux-shared:compileDebugShaders NO-SOURCE
> Task :termux-shared:generateDebugAssets UP-TO-DATE
> Task :termux-shared:mergeDebugAssets UP-TO-DATE
> Task :terminal-view:mergeDebugAssets UP-TO-DATE
> Task :rmr:processDebugJavaRes NO-SOURCE
> Task :rafaelia:processDebugJavaRes NO-SOURCE
> Task :terminal-emulator:processDebugJavaRes NO-SOURCE
> Task :terminal-view:processDebugJavaRes NO-SOURCE
> Task :terminal-emulator:bundleLibRuntimeToJarDebug UP-TO-DATE
> Task :termux-shared:processDebugJavaRes NO-SOURCE
> Task :termux-shared:bundleLibRuntimeToJarDebug UP-TO-DATE
> Task :terminal-view:bundleLibRuntimeToJarDebug UP-TO-DATE
> Task :rafaelia:bundleLibRuntimeToJarDebug UP-TO-DATE
> Task :rmr:bundleLibRuntimeToJarDebug UP-TO-DATE
> Task :app:processDebugNavigationResources UP-TO-DATE
> Task :app:compileDebugNavigationResources UP-TO-DATE
> Task :rafaelia:configureNdkBuildDebug[arm64-v8a]
> Task :rmr:configureNdkBuildDebug[arm64-v8a]
> Task :app:generateDebugResValues UP-TO-DATE
> Task :app:mapDebugSourceSetPaths UP-TO-DATE
> Task :app:generateDebugResources UP-TO-DATE
> Task :rafaelia:buildNdkBuildDebug[arm64-v8a]
> Task :app:mergeDebugResources UP-TO-DATE
> Task :rafaelia:configureNdkBuildDebug[armeabi-v7a]
> Task :app:packageDebugResources UP-TO-DATE
> Task :app:parseDebugLocalResources UP-TO-DATE
> Task :rmr:buildNdkBuildDebug[arm64-v8a]
> Task :app:createDebugCompatibleScreenManifests UP-TO-DATE
> Task :app:extractDeepLinksDebug UP-TO-DATE
> Task :rmr:configureNdkBuildDebug[armeabi-v7a]
> Task :app:processDebugMainManifest UP-TO-DATE
> Task :app:processDebugManifest UP-TO-DATE
> Task :app:processDebugManifestForPackage UP-TO-DATE
> Task :rafaelia:buildNdkBuildDebug[armeabi-v7a]
> Task :rafaelia:configureNdkBuildDebug[x86]
> Task :rmr:buildNdkBuildDebug[armeabi-v7a]
> Task :rmr:configureNdkBuildDebug[x86]
> Task :rmr:buildNdkBuildDebug[x86]
> Task :rmr:configureNdkBuildDebug[x86_64]
> Task :rafaelia:buildNdkBuildDebug[x86]
> Task :rafaelia:configureNdkBuildDebug[x86_64]
> Task :rmr:buildNdkBuildDebug[x86_64]
> Task :rmr:mergeDebugJniLibFolders UP-TO-DATE
> Task :rmr:mergeDebugNativeLibs UP-TO-DATE
> Task :rmr:copyDebugJniLibsProjectOnly UP-TO-DATE
> Task :terminal-emulator:configureNdkBuildDebug[arm64-v8a]
> Task :app:processDebugResources UP-TO-DATE
> Task :rafaelia:buildNdkBuildDebug[x86_64]
> Task :rafaelia:mergeDebugJniLibFolders UP-TO-DATE
> Task :app:compileDebugJavaWithJavac UP-TO-DATE
> Task :rafaelia:mergeDebugNativeLibs UP-TO-DATE
> Task :app:mergeDebugShaders UP-TO-DATE
> Task :rafaelia:copyDebugJniLibsProjectOnly UP-TO-DATE
> Task :app:compileDebugShaders NO-SOURCE
> Task :app:generateDebugAssets UP-TO-DATE
> Task :terminal-view:mergeDebugJniLibFolders UP-TO-DATE
> Task :terminal-view:mergeDebugNativeLibs NO-SOURCE
> Task :terminal-view:copyDebugJniLibsProjectOnly UP-TO-DATE
> Task :termux-shared:configureNdkBuildDebug[arm64-v8a]
> Task :terminal-emulator:buildNdkBuildDebug[arm64-v8a]
> Task :app:mergeDebugAssets UP-TO-DATE
> Task :app:compressDebugAssets UP-TO-DATE
> Task :terminal-emulator:configureNdkBuildDebug[armeabi-v7a]
> Task :app:l8DexDesugarLibDebug UP-TO-DATE
> Task :app:processDebugJavaRes NO-SOURCE
> Task :termux-shared:buildNdkBuildDebug[arm64-v8a]
> Task :app:mergeDebugJavaResource UP-TO-DATE
> Task :termux-shared:configureNdkBuildDebug[armeabi-v7a]
> Task :terminal-emulator:buildNdkBuildDebug[armeabi-v7a]
> Task :terminal-emulator:configureNdkBuildDebug[x86]
> Task :app:checkDebugDuplicateClasses UP-TO-DATE
> Task :termux-shared:buildNdkBuildDebug[armeabi-v7a]
> Task :termux-shared:configureNdkBuildDebug[x86]
> Task :app:desugarDebugFileDependencies UP-TO-DATE
> Task :terminal-emulator:buildNdkBuildDebug[x86]
> Task :terminal-emulator:configureNdkBuildDebug[x86_64]
> Task :termux-shared:buildNdkBuildDebug[x86]
> Task :termux-shared:configureNdkBuildDebug[x86_64]
> Task :app:mergeExtDexDebug UP-TO-DATE
> Task :app:mergeLibDexDebug UP-TO-DATE
> Task :app:dexBuilderDebug UP-TO-DATE
> Task :app:mergeProjectDexDebug UP-TO-DATE
> Task :app:configureNdkBuildDebug[arm64-v8a]
> Task :terminal-emulator:buildNdkBuildDebug[x86_64]
> Task :terminal-emulator:mergeDebugJniLibFolders UP-TO-DATE
> Task :terminal-emulator:mergeDebugNativeLibs UP-TO-DATE
> Task :terminal-emulator:copyDebugJniLibsProjectOnly UP-TO-DATE
> Task :termux-shared:buildNdkBuildDebug[x86_64]
> Task :termux-shared:mergeDebugJniLibFolders UP-TO-DATE
> Task :termux-shared:mergeDebugNativeLibs UP-TO-DATE
> Task :termux-shared:copyDebugJniLibsProjectOnly UP-TO-DATE
> Task :rmr:checkDebugAarMetadata UP-TO-DATE
> Task :rmr:stripDebugDebugSymbols UP-TO-DATE
> Task :rmr:copyDebugJniLibsProjectAndLocalJars UP-TO-DATE
> Task :app:buildNdkBuildDebug[arm64-v8a]
> Task :rmr:extractDebugAnnotations UP-TO-DATE
> Task :app:configureNdkBuildDebug[armeabi-v7a]
> Task :rafaelia:checkDebugAarMetadata UP-TO-DATE
> Task :rmr:extractDeepLinksForAarDebug UP-TO-DATE
> Task :rafaelia:stripDebugDebugSymbols UP-TO-DATE
> Task :rmr:mergeDebugGeneratedProguardFiles UP-TO-DATE
> Task :rafaelia:copyDebugJniLibsProjectAndLocalJars UP-TO-DATE
> Task :rmr:mergeDebugConsumerProguardFiles UP-TO-DATE
> Task :rmr:prepareDebugArtProfile UP-TO-DATE
> Task :rmr:prepareLintJarForPublish UP-TO-DATE
> Task :rmr:mergeDebugJavaResource UP-TO-DATE
> Task :rafaelia:extractDebugAnnotations UP-TO-DATE
> Task :rmr:syncDebugLibJars UP-TO-DATE
> Task :rafaelia:extractDeepLinksForAarDebug UP-TO-DATE
> Task :rafaelia:mergeDebugGeneratedProguardFiles UP-TO-DATE
> Task :rmr:bundleDebugAar UP-TO-DATE
> Task :rmr:assembleDebug UP-TO-DATE
> Task :rafaelia:mergeDebugConsumerProguardFiles UP-TO-DATE
> Task :terminal-emulator:checkDebugAarMetadata UP-TO-DATE
> Task :terminal-emulator:stripDebugDebugSymbols UP-TO-DATE
> Task :rafaelia:prepareDebugArtProfile UP-TO-DATE
> Task :terminal-emulator:copyDebugJniLibsProjectAndLocalJars UP-TO-DATE
> Task :rafaelia:prepareLintJarForPublish UP-TO-DATE
> Task :rafaelia:mergeDebugJavaResource UP-TO-DATE
> Task :rafaelia:syncDebugLibJars UP-TO-DATE
> Task :rafaelia:bundleDebugAar UP-TO-DATE
> Task :terminal-emulator:extractDebugAnnotations UP-TO-DATE
> Task :rafaelia:assembleDebug UP-TO-DATE
> Task :terminal-emulator:extractDeepLinksForAarDebug UP-TO-DATE
> Task :terminal-view:checkDebugAarMetadata UP-TO-DATE
> Task :terminal-emulator:mergeDebugGeneratedProguardFiles UP-TO-DATE
> Task :terminal-view:stripDebugDebugSymbols NO-SOURCE
> Task :terminal-emulator:mergeDebugConsumerProguardFiles UP-TO-DATE
> Task :terminal-emulator:prepareDebugArtProfile UP-TO-DATE
> Task :terminal-view:copyDebugJniLibsProjectAndLocalJars UP-TO-DATE
> Task :terminal-emulator:prepareLintJarForPublish UP-TO-DATE
> Task :terminal-emulator:mergeDebugJavaResource UP-TO-DATE
> Task :terminal-view:extractDebugAnnotations UP-TO-DATE
> Task :terminal-view:extractDeepLinksForAarDebug UP-TO-DATE
> Task :terminal-emulator:syncDebugLibJars UP-TO-DATE
> Task :terminal-view:mergeDebugGeneratedProguardFiles UP-TO-DATE
> Task :terminal-emulator:bundleDebugAar UP-TO-DATE
> Task :terminal-emulator:assembleDebug UP-TO-DATE
> Task :terminal-view:mergeDebugConsumerProguardFiles UP-TO-DATE
> Task :terminal-view:prepareDebugArtProfile UP-TO-DATE
> Task :terminal-view:prepareLintJarForPublish UP-TO-DATE
> Task :terminal-view:mergeDebugJavaResource UP-TO-DATE
> Task :termux-shared:checkDebugAarMetadata UP-TO-DATE
> Task :terminal-view:syncDebugLibJars UP-TO-DATE
> Task :terminal-view:bundleDebugAar UP-TO-DATE
> Task :termux-shared:stripDebugDebugSymbols UP-TO-DATE
> Task :terminal-view:assembleDebug UP-TO-DATE
> Task :termux-shared:copyDebugJniLibsProjectAndLocalJars UP-TO-DATE
> Task :termux-shared:extractDebugAnnotations UP-TO-DATE
> Task :termux-shared:extractDeepLinksForAarDebug UP-TO-DATE
> Task :termux-shared:mergeDebugGeneratedProguardFiles UP-TO-DATE
> Task :termux-shared:mergeDebugConsumerProguardFiles UP-TO-DATE
> Task :termux-shared:prepareDebugArtProfile UP-TO-DATE
> Task :termux-shared:prepareLintJarForPublish UP-TO-DATE
> Task :termux-shared:mergeDebugJavaResource UP-TO-DATE
> Task :termux-shared:syncDebugLibJars UP-TO-DATE
> Task :termux-shared:bundleDebugAar UP-TO-DATE
> Task :termux-shared:assembleDebug UP-TO-DATE
> Task :app:buildNdkBuildDebug[armeabi-v7a]
> Task :app:configureNdkBuildDebug[x86]
> Task :app:buildNdkBuildDebug[x86]
> Task :app:configureNdkBuildDebug[x86_64]
> Task :app:buildNdkBuildDebug[x86_64]
> Task :app:mergeDebugJniLibFolders UP-TO-DATE
> Task :app:mergeDebugNativeLibs UP-TO-DATE
> Task :app:stripDebugDebugSymbols UP-TO-DATE
> Task :app:validateSigningDebug UP-TO-DATE
> Task :app:writeDebugAppMetadata UP-TO-DATE
> Task :app:writeDebugSigningConfigVersions UP-TO-DATE
> Task :app:packageDebug UP-TO-DATE
> Task :app:createDebugApkListingFileRedirect UP-TO-DATE
> Task :app:assembleDebug UP-TO-DATE

[Incubating] Problems report is available at: file:///workspace/termux-app-rafacodephi/build/reports/problems/problems-report.html

Deprecated Gradle features were used in this build, making it incompatible with Gradle 9.0.

You can use '--warning-mode all' to show the individual deprecation warnings and determine if they come from your own scripts or plugins.

For more on this, please refer to https://docs.gradle.org/8.14.3/userguide/command_line_interface.html#sec:command_line_warnings in the Gradle documentation.

BUILD SUCCESSFUL in 32s
234 actionable tasks: 44 executed, 190 up-to-date
```

## APK Result
- APK generated: **Yes**
- APK path: `/workspace/termux-app-rafacodephi/app/build/outputs/apk/debug/termux-rafcodephi-debug-armeabi-v7a.apk`
