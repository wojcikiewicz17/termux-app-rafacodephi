#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_PATH="$ROOT_DIR/Arme/manifest.schema.json"
MANIFEST_PATH="$ROOT_DIR/Arme/manifest.json"

python3 - <<'PY' "$ROOT_DIR" "$SCHEMA_PATH" "$MANIFEST_PATH"
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
schema_path = Path(sys.argv[2])
manifest_path = Path(sys.argv[3])

schema = json.loads(schema_path.read_text(encoding='utf-8'))
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))

required_root = schema.get('required', [])
for key in required_root:
    if key not in manifest:
        raise SystemExit(f"ERRO: campo obrigatório ausente no manifest: {key}")

required_item = schema['properties']['itens']['items']['required']
allowed_tipo = set(schema['properties']['itens']['items']['properties']['tipo']['enum'])
allowed_status = set(schema['properties']['itens']['items']['properties']['status']['enum'])

items = manifest.get('itens')
if not isinstance(items, list):
    raise SystemExit('ERRO: campo itens deve ser uma lista')

manifest_files = set()
for idx, item in enumerate(items):
    if not isinstance(item, dict):
        raise SystemExit(f'ERRO: item {idx} não é objeto')
    missing = [k for k in required_item if k not in item]
    if missing:
        raise SystemExit(f'ERRO: item {idx} sem campos obrigatórios: {missing}')
    extra = set(item.keys()) - set(required_item)
    if extra:
        raise SystemExit(f'ERRO: item {idx} com campos extras: {sorted(extra)}')
    if item['tipo'] not in allowed_tipo:
        raise SystemExit(f"ERRO: item {idx} tipo inválido: {item['tipo']}")
    if item['status'] not in allowed_status:
        raise SystemExit(f"ERRO: item {idx} status inválido: {item['status']}")
    if not isinstance(item['pode_compilar'], bool) or not isinstance(item['pode_extrair'], bool):
        raise SystemExit(f'ERRO: item {idx} flags booleanas inválidas')
    manifest_files.add(item['arquivo'])

expected_files = set()
for relative in ('Arme', 'Arme/Add'):
    base = root / relative
    for path in base.iterdir():
        if path.is_file() and path.name not in ('manifest.json', 'manifest.schema.json'):
            expected_files.add(f'{relative}/{path.name}')

missing_files = sorted(expected_files - manifest_files)
extra_files = sorted(manifest_files - expected_files)
if missing_files:
    raise SystemExit('ERRO: arquivos sem classificação no manifest: ' + ', '.join(missing_files))
if extra_files:
    raise SystemExit('ERRO: entradas no manifest sem arquivo correspondente: ' + ', '.join(extra_files))

legacy = [i for i in items if i['arquivo'] == 'Arme/compilador_asm_legacy.sh']
if not legacy:
    raise SystemExit('ERRO: compilador_asm_legacy.sh não encontrado no manifest')
legacy_item = legacy[0]
if legacy_item['tipo'] != 'legado' or legacy_item['pode_compilar']:
    raise SystemExit('ERRO: compilador_asm_legacy.sh deve ser legado com pode_compilar=false')

print(f'OK: manifest validado com {len(items)} itens e cobertura completa de Arme/ e Arme/Add/.')
PY
