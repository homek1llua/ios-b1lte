#!/usr/bin/env bash
# Turn upstream Mu-Silicium beyond1ltePkg into the B2L Galaxy S10 platform.
# Upstream's DXE heap (0xC9240000..0xCCE40000) overlaps the display reservation
# at 0xCA000000 and its FD is 2 MiB. uefi-platform/beyond1lte/MemoryMapLib.c is
# the memory map of the owner's working beyond2ltePkg firmware (4 MiB FD, heap
# at 0xCB400000, B2L EL2 + RT log at 0xCF000000), read from a BOOT dump.
#
#   make-b1l-platform.sh WORKSPACE
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ws="$1"
pkg="$ws/Platforms/Samsung/beyond1ltePkg"
[[ -f "$pkg/beyond1lte.dsc" ]] || { echo "Not a Mu-Silicium tree with beyond1ltePkg: $ws" >&2; exit 1; }
cp "$repo_root/uefi-platform/beyond1lte/MemoryMapLib.c" "$pkg/Library/MemoryMapLib/MemoryMapLib.c"
# The stack follows the 4 MiB FD (0xC9000000..0xC9400000).
sed -i.bak 's/PcdCPUCoresStackBase|0xC9200000/PcdCPUCoresStackBase|0xC9400000/' "$pkg/beyond1lte.dsc" && rm -f "$pkg/beyond1lte.dsc.bak"
grep -q 'PcdCPUCoresStackBase|0xC9400000' "$pkg/beyond1lte.dsc" || { echo "Stack base not updated" >&2; exit 1; }
# Upstream build fix: UfsDxe calls MicroSecondDelay without linking TimerLib.
ufs="$ws/Silicon/Samsung/SamsungPkg/Drivers/UfsDxe/UfsDxe.inf"
grep -qE '^\s*TimerLib\s*$' "$ufs" || sed -i.bak 's/^\(\s*\)MemoryAllocationLib\s*$/\1MemoryAllocationLib\n\1TimerLib/' "$ufs" && rm -f "$ufs.bak"
grep -qE '^\s*TimerLib\s*$' "$ufs" || { echo "UfsDxe TimerLib fix not applied" >&2; exit 1; }
# Storage. Upstream beyond1ltePkg puts no UFS, disk, partition or FAT driver in the
# firmware, and SamsungPkg has no 9820 PlatformUfsLib. B2LUfsDxe is the owner's 9820
# UfsDxe (scripts/extract-fw-drivers.py) with its GPIO bank IDs fixed for upstream
# GpioDxe (scripts/patch-ufs-gpio-banks.py); the owner's other Samsung and keypad
# drivers use the same old numbering and are not used. Disk drivers are upstream.
mkdir -p "$pkg/Binary"
cp -R "$repo_root/uefi-platform/beyond1lte/binaries/"* "$pkg/Binary/"
PKG="$pkg" python3 - <<'PY'
import os, re
from pathlib import Path
pkg = Path(os.environ['PKG'])
# Samsung/keypad drivers stay upstream. Upstream HsI2cDxe has no 9820 HsI2cLib, so HSI2C
# (and the touch driver after it) come from the owner's firmware.
swap = {'SamsungPkg/Drivers/HsI2cDxe/HsI2cDxe.inf': 'B2LHsI2cDxe'}
binf = lambda n: f'beyond1ltePkg/Binary/{n}/{n}.inf'
storage = ('\n  # B2L storage stack\n'
           '  INF MdeModulePkg/Universal/Disk/DiskIoDxe/DiskIoDxe.inf\n'
           '  INF MdeModulePkg/Universal/Disk/PartitionDxe/PartitionDxe.inf\n\n'
           f'  INF {binf("B2LUfsDxe")}\n\n'
           '  INF MdeModulePkg/Universal/Disk/UnicodeCollation/EnglishDxe/EnglishDxe.inf\n'
           '  INF FatPkg/EnhancedFatDxe/Fat.inf\n')
for inc in ('APRIORI.inc', 'DXE.inc'):
    path = pkg / 'Include' / inc; text = path.read_text()
    if 'B2LTouchDxe' in text: continue
    for old, new in swap.items():
        line = f'  INF {old}\n'
        if text.count(line) != 1: raise SystemExit(f'{inc}: expected one {old}')
        extra = f'  INF {binf("B2LTouchDxe")}\n' if new == 'B2LHsI2cDxe' else ''
        text = text.replace(line, f'  INF {binf(new)}\n' + extra)
    anchor = '  INF SamsungPkg/Drivers/PmicDxe/PmicDxe.inf\n'
    text = text.replace(anchor, anchor + storage)
    path.write_text(text)
dsc = pkg / 'beyond1lte.dsc'; text = dsc.read_text()
if 'B2LTouchDxe/B2LTouchDxe.inf' not in text:
    names = sorted(d.name for d in (pkg / 'Binary').iterdir() if (d / f'{d.name}.inf').is_file())
    text += '\n[Components]\n' + ''.join(f'  {binf(n)}\n' for n in names)
    dsc.write_text(text)
PY
echo "beyond1ltePkg prepared for B2L"
