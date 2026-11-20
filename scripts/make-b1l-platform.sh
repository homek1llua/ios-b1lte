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
# Storage stack. Upstream beyond1ltePkg puts no UFS, disk, partition or FAT driver in
# the firmware volume, and SamsungPkg has no 9820 PlatformUfsLib; the loader then sees
# no block devices. Use the owner's working 9820 UfsDxe binary (B2LUfsDxe) and the
# upstream disk drivers, in the x1sPkg order.
mkdir -p "$pkg/Binary/B2LUfsDxe"
cp "$repo_root/uefi-platform/beyond1lte/B2LUfsDxe/"* "$pkg/Binary/B2LUfsDxe/"
storage='  # B2L storage stack
  INF MdeModulePkg/Universal/Disk/DiskIoDxe/DiskIoDxe.inf
  INF MdeModulePkg/Universal/Disk/PartitionDxe/PartitionDxe.inf

  INF beyond1ltePkg/Binary/B2LUfsDxe/B2LUfsDxe.inf

  INF MdeModulePkg/Universal/Disk/UnicodeCollation/EnglishDxe/EnglishDxe.inf
  INF FatPkg/EnhancedFatDxe/Fat.inf
'
for inc in "$pkg/Include/APRIORI.inc" "$pkg/Include/DXE.inc"; do
  grep -q 'B2L storage stack' "$inc" && continue
  STORAGE="$storage" python3 - "$inc" <<'PY'
import os, sys
path = sys.argv[1]; text = open(path).read()
anchor = "  INF SamsungPkg/Drivers/PmicDxe/PmicDxe.inf\n"
if text.count(anchor) != 1: sys.exit(f"{path}: PmicDxe anchor not found once")
open(path, "w").write(text.replace(anchor, anchor + "\n" + os.environ["STORAGE"]))
PY
done
grep -q 'B2LUfsDxe/B2LUfsDxe.inf' "$pkg/beyond1lte.dsc" ||
  printf '\n[Components]\n  beyond1ltePkg/Binary/B2LUfsDxe/B2LUfsDxe.inf\n' >> "$pkg/beyond1lte.dsc"
echo "beyond1ltePkg prepared for B2L"
