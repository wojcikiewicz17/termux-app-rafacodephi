# 🔧 GitHub Workflow: Build ARM32 Multi-Page (Unified)

## 📋 Sumário

Este é um **workflow YAML completo** que implementa o fix ARM32 multi-page com 4 stages:

```
Stage 1: Detect & Prepare    (Calcula page sizes dinamicamente)
   ↓
Stage 2: Build (Matrix)       (Compila ARM32 + ARM64 em paralelo)
   ↓
Stage 3: Validate             (Consolida relatórios + ELF check)
   ↓
Stage 4: Emulator Test        (Opcional: testa em emulador ARM32)
```

---

## 🚀 Como Usar

### **1. Criar arquivo no repositório**

Crie manualmente em:
```
.github/workflows/build-arm32-multipage.yml
```

### **2. Copiar conteúdo completo**

Copie todo o conteúdo do arquivo abaixo e cole no editor web do GitHub.

### **3. Executar workflow**

**Opção A: Automático (push)**
```bash
git push origin main
```

**Opção B: Manual (via CLI)**
```bash
gh workflow run build-arm32-multipage.yml \
  --ref main \
  -f force_arm32_only=false \
  -f custom_page_size_arm32=4096 \
  -f enable_emulator_test=false
```

**Opção C: Web UI**
- Vá para: `Actions` > `Build ARM32 Multi-Page` > `Run workflow`
- Configure inputs (opcional)
- Click "Run"

---

## 📊 O Que Faz

### **Stage 1: Detecção & Setup**
```yaml
Outputs:
  - build-matrix (JSON com ABIs)
  - page-sizes (JSON: arm32=4096, arm64=16384)
  - arm32-page-size
  - arm64-page-size
```

**Ações:**
- ✅ Parse `gradle.properties`
- ✅ Detecta ABIs configurados
- ✅ Calcula page sizes dinâmicos
- ✅ Gera matrix para Stage 2

---

### **Stage 2: Build (Matrix Strategy)**

**Para cada ABI (paralelo):**

```yaml
matrix:
  - abi: arm64-v8a
    arch: aarch64
    page_size: 16384
  
  - abi: armeabi-v7a
    arch: arm
    page_size: 4096
```

**Por ABI:**
1. Setup NDK
2. **Modifica `Android.mk` dinamicamente** com:
   ```makefile
   -Wl,-z,max-page-size=4096  # ARM32
   -Wl,-z,common-page-size=4096
   ```
3. Compila APK via `./gradlew assembleDebug`
4. **Valida ELF** com script Python
5. Gera `BUILD_REPORT_arm.txt`
6. Upload artifacts segmentados

---

### **Stage 3: Validação Consolidada**

```yaml
Ações:
  - Download todos artifacts
  - Parse validation JSONs
  - Consolida relatórios
  - Gera GitHub Summary automático
```

**Output:**
```
CONSOLIDATED_BUILD_REPORT.txt
├─ Build info por ABI
├─ Validation status
├─ ELF info
└─ Bootstrap metadata
```

---

### **Stage 4: Emulator Test (Opcional)**

```yaml
if: enable_emulator_test == 'true'
```

**Passos:**
1. Setup emulador ARM32 (API 24)
2. Cria AVD `arm32_test`
3. Inicia emulador
4. Instala APK ARM32
5. Testa execução

---

## 📈 Resultados Esperados

### **GitHub Actions UI**

```
✅ detect-and-prepare       (1m 30s)
   ├─ Checkout
   ├─ Detect & Prepare
   └─ Generate Summary

✅ build                     (5m - paralelo)
   ├─ arm64-v8a             (2m 45s)
   │  ├─ Setup Java/NDK
   │  ├─ Configure PageSize=16384
   │  ├─ Build APK
   │  ├─ Validate ELF
   │  └─ Upload artifacts
   │
   └─ armeabi-v7a           (2m 45s)
      ├─ Setup Java/NDK
      ├─ Configure PageSize=4096
      ├─ Build APK
      ├─ Validate ELF
      └─ Upload artifacts

✅ validate-consolidated    (1m)
   ├─ Download All Artifacts
   ├─ Consolidate Reports
   ├─ Create GitHub Summary
   └─ Upload Consolidated Report

⏭️  test-emulator           (skipped - disable por padrão)
```

### **GitHub Summary (Automático)**

```markdown
# ✅ Build Consolidation Report

## 🎯 Configuration
- **ARM32 Page Size**: 4096
- **ARM64 Page Size**: 16384

## 📦 Artifacts Generated
- `termux-rafcodephi-debug-armeabi-v7a.apk` (45.3 MB)
- `termux-rafcodephi-debug-arm64-v8a.apk` (46.1 MB)

## ✅ Validation Status
✅ **2 APK(s) validado(s) com sucesso**
```

### **Artifacts Download**

```
Actions > Run > Artifacts
├─ apk-arm-pagesize-4096/
│  ├─ termux-rafcodephi-debug-armeabi-v7a.apk
│  ├─ BUILD_REPORT_arm.txt
│  ├─ validation-arm.json
│  └─ build-arm.log
│
├─ apk-aarch64-pagesize-16384/
│  ├─ termux-rafcodephi-debug-arm64-v8a.apk
│  ├─ BUILD_REPORT_aarch64.txt
│  ├─ validation-aarch64.json
│  └─ build-aarch64.log
│
└─ consolidated-reports/
   ├─ CONSOLIDATED_BUILD_REPORT.txt
   └─ all-artifacts/
```

---

## 🔧 Inputs Customizáveis

### **`force_arm32_only`** (default: false)
```yaml
Compilar apenas ARM32 (pula ARM64)
- false: Compila ambos
- true: Apenas ARM32
```

### **`custom_page_size_arm32`** (default: 4096)
```yaml
Page size customizado para ARM32
- 4096: Padrão (Motorola E7 Power)
- Outro: Usar este valor
```

### **`enable_emulator_test`** (default: false)
```yaml
Executar testes em emulador
- false: Pula Stage 4
- true: Teste em emulador ARM32 (API 24)
```

---

## 📊 Metodologia Aplicada

| Aspecto | Implementação |
|---------|---|
| **Detecção Dinâmica** | Job separado com outputs + matrix |
| **Condicionality** | `strategy.matrix` por ABI |
| **Parallelização** | ARM32 + ARM64 simultâneos (~5m) |
| **Config Dinâmica** | Android.mk modificado per-ABI no-the-fly |
| **Validação** | ELF parse + Bootstrap metadata check |
| **Relatórios** | JSON + human-readable consolidados |
| **Summary** | GitHub Summary automático |
| **Artifacts** | Segmentados por ABI + page-size |
| **Logs** | Capturados em arquivo |
| **CI/CD** | Reutilizável + dispatch manual |

---

## 🎯 Próximos Passos

1. **Copiar conteúdo YAML** para `.github/workflows/build-arm32-multipage.yml`
2. **Push para main/develop**
3. **Aguardar workflow** (5-10 min primeira execução)
4. **Download APK validado**
5. **Testar em device ARM32**

---

## 🐛 Troubleshooting

### **Build falha no "Configure Page Size"**
```bash
→ Verificar se app/src/main/cpp/Android.mk existe
→ Não tem permissão de escrita?
```

### **APK validation falha**
```bash
→ Executar manualmente:
python3 scripts/validate_arm32_apk.py --apk <apk> --arch arm
```

### **Emulator test não dispara**
```bash
→ Confirmar: enable_emulator_test=true no workflow_dispatch
→ Requer ~15min de setup adicional
```

---

**Pronto para copiar e usar! 🚀**
