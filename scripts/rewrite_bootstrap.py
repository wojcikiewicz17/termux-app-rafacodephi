#!/usr/bin/env python3
import argparse, os, stat, zipfile, subprocess, shutil, sys
from pathlib import Path

TEXT_EXTS = {'.sh', '.conf', '.properties', '.list'}
TEXT_NAMES = {'sources.list', 'profile', 'motd', 'pkg', 'apt'}
REPL = [
    ('/data/data/com.termux/files/usr', '/data/data/com.termux.rafacodephi/files/usr'),
    ('/data/data/com.termux/files/home', '/data/data/com.termux.rafacodephi/files/home'),
    ('com.termux', 'com.termux.rafacodephi'),
]
ARCH_MAP = {'arm':'ARM','aarch64':'AArch64','i686':'Intel 80386','x86_64':'Advanced Micro Devices X86-64'}
ELF_LEGACY_PREFIX_NEEDLES = (
    b'/data/data/com.termux/files/usr',
    b'/data/data/com.termux/files/home',
    b'/data/user/0/com.termux/files/usr',
    b'/data/user/0/com.termux/files/home',
)
# Paths intentionally allowlisted because the upstream binaries contain
# hardcoded documentation/help defaults that are not runtime critical.
ELF_LEGACY_ALLOWLIST = {
    "bin/addpart": "upstream util-linux binary embeds legacy termux default path in help text only",
}


def is_elf(p: Path):
    try:
        with p.open('rb') as f:
            return f.read(4) == b'\x7fELF'
    except Exception:
        return False

def is_text(path: Path):
    if path.suffix in TEXT_EXTS or path.name in TEXT_NAMES:
        return True
    if shutil.which('file') is None:
        return False
    try:
        out = subprocess.run(['file','--mime-type','-b',str(path)],capture_output=True,text=True,check=False)
        return out.stdout.strip().startswith('text/')
    except Exception:
        return False



def extract_zip_preserve_symlinks(zip_path: Path, dest: Path):
    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            out = dest / info.filename
            if info.is_dir():
                out.mkdir(parents=True, exist_ok=True)
                continue
            out.parent.mkdir(parents=True, exist_ok=True)
            mode = (info.external_attr >> 16) & 0o170000
            is_link = mode == 0o120000
            data = zf.read(info)
            if is_link:
                target = data.decode('utf-8')
                if out.exists() or out.is_symlink():
                    out.unlink()
                os.symlink(target, out)
            else:
                with out.open('wb') as f:
                    f.write(data)
                perm = (info.external_attr >> 16) & 0o777
                if perm:
                    out.chmod(perm)

def deterministic_zip(src: Path, outzip: Path):
    with zipfile.ZipFile(outzip, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for p in sorted(src.rglob('*')):
            rel = p.relative_to(src).as_posix()
            zi = zipfile.ZipInfo(rel)
            zi.date_time = (1980,1,1,0,0,0)
            st = p.lstat()
            if stat.S_ISLNK(st.st_mode):
                zi.create_system = 3
                zi.external_attr = (0o120777 << 16)
                zf.writestr(zi, os.readlink(p).encode('utf-8'))
            elif p.is_file():
                zi.create_system = 3
                zi.external_attr = ((st.st_mode & 0xFFFF) << 16)
                with p.open('rb') as f:
                    zf.writestr(zi, f.read())

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--input', required=True)
    ap.add_argument('--output', required=True)
    ap.add_argument('--arch', required=True)
    ap.add_argument('--abi', required=True)
    ap.add_argument('--package-name', default='com.termux.rafacodephi')
    ap.add_argument('--prefix', default='/data/data/com.termux.rafacodephi/files/usr')
    ap.add_argument('--home', default='/data/data/com.termux.rafacodephi/files/home')
    ap.add_argument('--page-size', default='16384')
    ap.add_argument('--variant', default='apt-android-7')
    ap.add_argument('--strict-elf-prefix-check', action='store_true',
                    help='Fail when legacy com.termux prefix is found inside ELF payload bytes')
    ap.add_argument('--workdir', default='build/bootstrap-rewrite')
    ap.add_argument('--report-dir', default='build/reports/bootstrap-rewrite')
    args = ap.parse_args()

    staging = Path(args.workdir) / args.arch
    if staging.exists(): shutil.rmtree(staging)
    staging.mkdir(parents=True, exist_ok=True)
    extract_zip_preserve_symlinks(Path(args.input), staging)

    rep = Path(args.report_dir); rep.mkdir(parents=True, exist_ok=True)
    text_report = rep / 'bootstrap-text-rewrite-report.txt'
    elf_report = rep / 'bootstrap-elf-report.txt'
    changed = []
    elf_lines = []
    legacy_hits = []
    scanned_files = 0

    for p in sorted(staging.rglob('*')):
        if p.is_dir() or p.is_symlink(): continue
        scanned_files += 1
        rel = p.relative_to(staging)
        if is_elf(p):
            if shutil.which('file') is not None:
                out = subprocess.run(['file',str(p)],capture_output=True,text=True).stdout.strip()
            else:
                out = 'ELF (file utility unavailable)'
            elf_lines.append(f'{rel}: {out}')
            hdr = subprocess.run(['readelf','-h',str(p)],capture_output=True,text=True).stdout
            mach_ok = ARCH_MAP.get(args.arch,'') in hdr
            if not mach_ok:
                raise SystemExit(f'ELF ABI mismatch: {rel}')
            ph = subprocess.run(['readelf','-l',str(p)],capture_output=True,text=True).stdout
            for line in ph.splitlines():
                if ' LOAD ' in line and 'Align' not in line:
                    pass
            elf_bytes = p.read_bytes()
            rel_str = rel.as_posix()
            for needle in ELF_LEGACY_PREFIX_NEEDLES:
                start = 0
                while True:
                    idx = elf_bytes.find(needle, start)
                    if idx == -1:
                        break
                    legacy_hits.append({
                        "file": rel_str,
                        "needle": needle.decode('utf-8'),
                        "offset": idx,
                        "allowlisted": rel_str in ELF_LEGACY_ALLOWLIST,
                        "reason": ELF_LEGACY_ALLOWLIST.get(rel_str, ""),
                    })
                    start = idx + 1
            continue
        if p.suffix in {'.so','.a','.o'}:
            continue
        if is_text(p):
            raw = p.read_text(encoding='utf-8', errors='ignore')
            new = raw
            for a,b in REPL: new = new.replace(a,b)
            if p.name == 'BUILD_ONLY':
                new = '0\n'
            if new != raw:
                p.write_text(new, encoding='utf-8')
                changed.append(str(rel))

    (staging/'BOOTSTRAP_INFO').write_text(
        f'TERMUX_PACKAGE_NAME={args.package_name}\nTERMUX_ARCH={args.arch}\nTERMUX_ABI={args.abi}\nTERMUX_PACKAGE_VARIANT={args.variant}\nTERMUX_PREFIX={args.prefix}\nTERMUX_HOME={args.home}\nTERMUX_PAGE_SIZE={args.page_size}\nBOOTSTRAP_KIND=rewritten\nBOOTSTRAP_RUNTIME_READY=1\nBOOTSTRAP_REWRITE_VERSION=1\n', encoding='utf-8')
    bo = staging/'BUILD_ONLY'
    if bo.exists(): bo.write_text('0\n', encoding='utf-8')

    runtime_candidates = {
        'bin/sh': ('bin/sh', 'usr/bin/sh'),
        'bin/pkg': ('bin/pkg', 'usr/bin/pkg'),
    }
    for req, candidates in runtime_candidates.items():
        rp = next((staging / c for c in candidates if (staging / c).exists()), None)
        if rp is None or is_text(rp):
            joined = ', '.join(candidates)
            raise SystemExit(f'Missing real runtime binary: {req} (checked: {joined})')

    for p in staging.rglob('*'):
        if p.is_file() and is_text(p):
            t = p.read_text(encoding='utf-8', errors='ignore')
            if '/data/data/com.termux/files/usr' in t:
                raise SystemExit(f'Legacy prefix leakage: {p.relative_to(staging)}')

    blocked = [h for h in legacy_hits if not h["allowlisted"]]
    allowed = [h for h in legacy_hits if h["allowlisted"]]
    if blocked:
        print("ELF files blocked due to non-allowlisted hardcoded legacy prefixes:", file=sys.stderr)
        for h in blocked:
            print(f" - {h['file']} offset=0x{h['offset']:x} needle={h['needle']}", file=sys.stderr)
        raise SystemExit(
            f"rewriteBootstraps failed: {len(blocked)} non-allowlisted ELF legacy prefix occurrence(s) found")
    if allowed:
        print("ELF legacy prefix occurrences (allowlisted):", file=sys.stderr)
        for h in allowed:
            print(
                f" - {h['file']} offset=0x{h['offset']:x} needle={h['needle']} reason={h['reason']}",
                file=sys.stderr,
            )

    deterministic_zip(staging, Path(args.output))
    text_report.write_text('\n'.join(changed)+'\n', encoding='utf-8')
    elf_report.write_text('\n'.join(elf_lines)+'\n', encoding='utf-8')
    print(
        f"[rewrite_bootstrap] zip={args.input} scanned={scanned_files} legacy_found={len(legacy_hits)} "
        f"rewritten_text={len(changed)} blocked={len(blocked)} allowlisted={len(allowed)}"
    )
    print(f'rewritten: {args.output}')

if __name__ == '__main__':
    main()
