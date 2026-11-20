#!/usr/bin/env python3
"""Extract DXE drivers (PE32 + DXE_DEPEX) from a working Silicium BOOT image.

Used to carry the owner's 9820 SamsungPkg drivers (built from their beyond2ltePkg
tree) into the S10 firmware: upstream Mu-Silicium lacks a 9820 PlatformUfsLib and
its GPIO/I2C drivers do not match the owner's UFS driver.

  extract-fw-drivers.py BOOT_IMG OUTDIR NAME...
Writes OUTDIR/B2L<NAME>/{<NAME>.efi,<NAME>.depex,B2L<NAME>.inf} with a new FILE_GUID.
"""
import hashlib, lzma, re, struct, sys, uuid
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from fvparse import fv_files, sections, ui_name

boot, out, names = Path(sys.argv[1]).read_bytes(), Path(sys.argv[2]), sys.argv[3:]
page = struct.unpack_from('<I', boot, 36)[0]
kernel = boot[page:page + struct.unpack_from('<I', boot, 8)[0]]
fd = kernel[kernel.find(b'_FVH') - 40:][:0x400000]
volume = None
for m in re.finditer(rb'\x5d\x00\x00', fd):
    try:
        v = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE).decompress(fd[m.start():], max_length=64 << 20)
    except lzma.LZMAError:
        continue
    if b'_FVH' in v and len(v) > 100000:
        volume = v[v.find(b'_FVH') - 40:]; break
if volume is None: sys.exit('no compressed firmware volume found')
found = {}
for name, typ, body, raw in fv_files(volume):
    secs = sections(body)
    found[ui_name(secs)] = secs
for n in names:
    if n not in found: sys.exit(f'{n} not in firmware')
    pe = [b for t, b, _ in found[n] if t == 0x10]
    dep = [b for t, b, _ in found[n] if t == 0x13]
    d = out / f'B2L{n}'; d.mkdir(parents=True, exist_ok=True)
    (d / f'{n}.efi').write_bytes(pe[0])
    lines = [f'  PE32|{n}.efi|*']
    if dep:
        (d / f'{n}.depex').write_bytes(dep[0]); lines.append(f'  DXE_DEPEX|{n}.depex|*')
    guid = str(uuid.uuid5(uuid.NAMESPACE_URL, f'b2l-firmware-binary/{n}')).upper()
    sha = hashlib.sha256(pe[0]).hexdigest()
    (d / f'B2L{n}.inf').write_text(f"""## @file
#  {n} taken unchanged from the owner's working beyond2ltePkg firmware (BOOT dump of
#  2026-11-20, Exynos 9820). SHA-256 of {n}.efi: {sha}
##
[Defines]
  INF_VERSION    = 0x0001001B
  BASE_NAME      = B2L{n}
  FILE_GUID      = {guid}
  MODULE_TYPE    = DXE_DRIVER
  VERSION_STRING = 1.0

[Binaries.AARCH64]
""" + '\n'.join(lines) + '\n')
    print(f'B2L{n}: {len(pe[0])} bytes, depex {len(dep[0]) if dep else 0}, {sha[:12]}')
