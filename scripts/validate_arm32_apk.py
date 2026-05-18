#!/usr/bin/env python3
"""
🔧 ARM32 Multi-Page Size Validator
Valida APK e detecta incompatibilidades de page size antes do deploy

Uso:
  python3 scripts/validate_arm32_apk.py --apk termux-debug.apk --arch arm32
"""

import argparse
import struct
import zipfile
import subprocess
import sys
import json
from pathlib import Path
from typing import Dict, List, Tuple, Optional
import logging

# ════════════════════════════════════════════════════════════════════════════
# SETUP
# ════════════════════════════════════════════════════════════════════════════

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)

# ELF Constants
ELF_MAGIC = b'\x7fELF'
ELFCLASS32 = 1
ELFCLASS64 = 2
ET_DYN = 3  # Shared object
PT_LOAD = 1

# ════════════════════════════════════════════════════════════════════════════
# ELF Validator
# ════════════════════════════════════════════════════════════════════════════

class ELFValidator:
    """Validador de binários ELF"""
    
    def __init__(self, so_path: Path):
        self.so_path = so_path
        self.data = so_path.read_bytes()
        self.is_valid = False
        self.arch = None
        self.page_size = None
        self.load_segments = []
        self._parse()
    
    def _parse(self):
        """Parse ELF header"""
        if not self.data.startswith(ELF_MAGIC):
            logger.warning(f"❌ {self.so_path.name}: Não é um ELF válido")
            return
        
        # Classe (32/64 bit)
        ei_class = self.data[4]
        self.arch = "32-bit" if ei_class == ELFCLASS32 else "64-bit"
        
        # Endianness
        ei_data = self.data[5]
        little_endian = ei_data == 1
        fmt = '<' if little_endian else '>'
        
        # E_machine (tipo de arquitetura)
        e_machine = struct.unpack(fmt + 'H', self.data[18:20])[0]
        if e_machine == 40:  # EM_ARM
            self.arch = "ARM32"
        elif e_machine == 0xB7:  # EM_AARCH64
            self.arch = "ARM64"
        elif e_machine == 3:  # EM_386
            self.arch = "x86"
        elif e_machine == 62:  # EM_X86_64
            self.arch = "x86_64"
        
        self.is_valid = True
        self._extract_load_segments(fmt)
    
    def _extract_load_segments(self, fmt: str):
        """Extrair LOAD segments para análise de page size"""
        ei_class = self.data[4]
        
        if ei_class == ELFCLASS32:
            # 32-bit: e_phoff at 0x1C, e_phentsize at 0x2A
            e_phoff = struct.unpack(fmt + 'I', self.data[0x1C:0x20])[0]
            e_phentsize = struct.unpack(fmt + 'H', self.data[0x2A:0x2C])[0]
            e_phnum = struct.unpack(fmt + 'H', self.data[0x2C:0x2E])[0]
        else:
            # 64-bit: e_phoff at 0x20, e_phentsize at 0x36
            e_phoff = struct.unpack(fmt + 'Q', self.data[0x20:0x28])[0]
            e_phentsize = struct.unpack(fmt + 'H', self.data[0x36:0x38])[0]
            e_phnum = struct.unpack(fmt + 'H', self.data[0x38:0x3A])[0]
        
        for i in range(e_phnum):
            p_offset = e_phoff + i * e_phentsize
            p_type = struct.unpack(fmt + 'I', self.data[p_offset:p_offset+4])[0]
            
            if p_type == PT_LOAD:
                if ei_class == ELFCLASS32:
                    p_vaddr = struct.unpack(fmt + 'I', self.data[p_offset+8:p_offset+12])[0]
                else:
                    p_vaddr = struct.unpack(fmt + 'Q', self.data[p_offset+8:p_offset+16])[0]
                
                self.load_segments.append({
                    'vaddr': p_vaddr,
                    'align': p_vaddr & 0xFFF  # Últimos 12 bits = alinhamento
                })
        
        # Detectar page size pelo alinhamento
        if self.load_segments:
            alignments = [s['align'] for s in self.load_segments]
            # Se todos os segmentos estão alinhados a 16KB (0x4000)
            if all(addr & 0xFFFF == 0 for addr in [s['vaddr'] for s in self.load_segments]):
                self.page_size = 16384
            else:
                self.page_size = 4096

# ════════════════════════════════════════════════════════════════════════════
# Bootstrap Validator
# ════════════════════════════════════════════════════════════════════════════

class BootstrapValidator:
    """Validador de bootstrap metadata"""
    
    def __init__(self, apk_path: Path, arch: str):
        self.apk_path = apk_path
        self.arch = arch
        self.bootstrap_info = {}
        self._extract()
    
    def _extract(self):
        """Extrair BOOTSTRAP_INFO do APK"""
        bootstrap_name = f"bootstrap-{self.arch}.zip"
        
        try:
            with zipfile.ZipFile(self.apk_path, 'r') as apk_z:
                # Procurar bootstrap no assets
                for name in apk_z.namelist():
                    if name.endswith(bootstrap_name):
                        bootstrap_data = apk_z.read(name)
                        break
                else:
                    logger.warning(f"⚠️  {bootstrap_name} não encontrado no APK")
                    return
        except Exception as e:
            logger.error(f"❌ Erro ao ler APK: {e}")
            return
        
        # Extrair BOOTSTRAP_INFO do zip
        try:
            with zipfile.ZipFile(bootstrap_data, 'r') as boot_z:
                if 'BOOTSTRAP_INFO' in boot_z.namelist():
                    info_text = boot_z.read('BOOTSTRAP_INFO').decode('utf-8')
                    for line in info_text.split('\n'):
                        if '=' in line:
                            k, v = line.split('=', 1)
                            self.bootstrap_info[k.strip()] = v.strip()
        except Exception as e:
            logger.warning(f"⚠️  Erro ao ler BOOTSTRAP_INFO: {e}")

# ════════════════════════════════════════════════════════════════════════════
# Main Validator
# ════════════════════════════════════════════════════════════════════════════

def validate_apk(apk_path: Path, expected_arch: str = None) -> Dict:
    """
    Validar APK para compatibilidade ARM32 multi-page
    
    Args:
        apk_path: Caminho para o APK
        expected_arch: Arquitetura esperada (arm, aarch64, etc)
    
    Returns:
        Dict com resultados de validação
    """
    results = {
        'valid': False,
        'errors': [],
        'warnings': [],
        'infos': [],
        'elf_files': [],
        'bootstrap_info': {},
    }
    
    if not apk_path.exists():
        results['errors'].append(f"❌ APK não encontrado: {apk_path}")
        return results
    
    results['infos'].append(f"📦 Validando: {apk_path.name}")
    results['infos'].append(f"📊 Tamanho: {apk_path.stat().st_size / 1024 / 1024:.2f} MB")
    
    # Extrair e validar .so files
    try:
        with zipfile.ZipFile(apk_path, 'r') as z:
            so_files = [n for n in z.namelist() if n.endswith('.so')]
            
            if not so_files:
                results['errors'].append("❌ Nenhuma biblioteca nativa (.so) encontrada")
                return results
            
            results['infos'].append(f"✅ {len(so_files)} arquivo(s) .so encontrado(s)")
            
            # Validar cada .so
            for so_name in so_files:
                # Extrair para temp
                so_data = z.read(so_name)
                so_path = Path(f"/tmp/{Path(so_name).name}")
                so_path.write_bytes(so_data)
                
                validator = ELFValidator(so_path)
                
                if not validator.is_valid:
                    results['warnings'].append(f"⚠️  {so_name}: ELF inválido")
                    continue
                
                elf_info = {
                    'name': so_name,
                    'arch': validator.arch,
                    'page_size': validator.page_size,
                    'valid': True,
                }
                results['elf_files'].append(elf_info)
                
                logger.info(f"✅ {so_name}")
                logger.info(f"   Arch: {validator.arch}")
                logger.info(f"   Page Size: {validator.page_size}")
                
                # Validação de compatibilidade
                if expected_arch == 'arm' and validator.arch != 'ARM32':
                    results['errors'].append(
                        f"❌ {so_name}: esperado ARM32, encontrado {validator.arch}"
                    )
                elif expected_arch == 'aarch64' and validator.arch != 'ARM64':
                    results['errors'].append(
                        f"❌ {so_name}: esperado ARM64, encontrado {validator.arch}"
                    )
                
                # Validação de page size
                if validator.arch == 'ARM32' and validator.page_size == 16384:
                    results['errors'].append(
                        f"❌ {so_name}: ARM32 com 16KB page size (incompatível com Motorola E7 Power)"
                    )
                elif validator.arch == 'ARM64' and validator.page_size == 4096:
                    results['warnings'].append(
                        f"⚠️  {so_name}: ARM64 com 4KB page size (Android 15+ requer 16KB)"
                    )
    
    except zipfile.BadZipFile:
        results['errors'].append("❌ APK não é um ZIP válido")
        return results
    except Exception as e:
        results['errors'].append(f"❌ Erro ao processar APK: {e}")
        return results
    
    # Validar Bootstrap
    for arch in ['arm', 'aarch64', 'x86', 'x86_64']:
        validator = BootstrapValidator(apk_path, arch)
        if validator.bootstrap_info:
            results['bootstrap_info'][arch] = validator.bootstrap_info
            
            # Validação de page size
            page_size = validator.bootstrap_info.get('TERMUX_PAGE_SIZE', '')
            if arch == 'arm' and page_size == '16384':
                results['errors'].append(
                    f"❌ bootstrap-arm.zip: page size 16384 (incompatível ARM32)"
                )
            elif arch == 'aarch64' and page_size != '16384':
                results['warnings'].append(
                    f"⚠️  bootstrap-aarch64.zip: page size {page_size} (Android 15+ usa 16384)"
                )
    
    # Resultado final
    results['valid'] = len(results['errors']) == 0
    
    return results

def main():
    parser = argparse.ArgumentParser(
        description='🔧 Validador ARM32 Multi-Page para APK Termux'
    )
    parser.add_argument('--apk', type=Path, required=True, help='Caminho do APK')
    parser.add_argument(
        '--arch', 
        choices=['arm', 'aarch64', 'x86', 'x86_64'],
        help='Arquitetura esperada'
    )
    parser.add_argument('--json', action='store_true', help='Saída em JSON')
    
    args = parser.parse_args()
    
    # Validar
    results = validate_apk(args.apk, args.arch)
    
    # Output
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print("\n" + "="*70)
        print("🔧 ARM32 Multi-Page Validator")
        print("="*70 + "\n")
        
        for info in results['infos']:
            print(info)
        
        print()
        for elf in results['elf_files']:
            print(f"  📄 {elf['name']}")
            print(f"     Arch: {elf['arch']}")
            print(f"     Page Size: {elf['page_size']}")
        
        if results['bootstrap_info']:
            print()
            print("📦 Bootstrap Info:")
            for arch, info in results['bootstrap_info'].items():
                print(f"  {arch}:")
                for k, v in info.items():
                    print(f"    {k}: {v}")
        
        if results['warnings']:
            print()
            print("⚠️  WARNINGS:")
            for w in results['warnings']:
                print(f"  {w}")
        
        if results['errors']:
            print()
            print("❌ ERRORS:")
            for e in results['errors']:
                print(f"  {e}")
        
        print()
        status = "✅ VÁLIDO" if results['valid'] else "❌ INVÁLIDO"
        print(f"Status: {status}")
        print("="*70 + "\n")
    
    return 0 if results['valid'] else 1

if __name__ == '__main__':
    sys.exit(main())
