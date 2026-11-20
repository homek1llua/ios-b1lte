#!/usr/bin/env python3
"""Fix the GPIO bank IDs in the owner's 9820 UfsDxe binary for upstream GpioDxe.

The binary was built in a tree whose EFI_GPIO_BANK_ID starts at A = 0 (its messages
name bank 3 "GPD0"); upstream SamsungPkg starts at BANK_ID_A = 1. Its five GPIO
protocol calls (pull/function on GPF3 pins 0 and 1 for REFCLK/RST_N, function on
GPD0 pin 2) therefore hit GPE3 and GPC0 upstream, and SetPull returns NOT_FOUND
("Failed to set GPIO pull for REFCLK"). Each patched word is checked first.

  patch-ufs-gpio-banks.py IN.efi OUT.efi
"""
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
d = bytearray(open(src, 'rb').read())
pe = struct.unpack_from('<I', d, 0x3c)[0]
nsec = struct.unpack_from('<H', d, pe + 6)[0]; opt = struct.unpack_from('<H', d, pe + 20)[0]
secs = []
for i in range(nsec):
    o = pe + 24 + opt + i * 40
    name = d[o:o + 8].rstrip(b'\0'); vsz, va, rsz, raw = struct.unpack_from('<IIII', d, o + 8)
    secs.append((name, va, rsz, raw))
def off(va):
    for name, sva, rsz, raw in secs:
        if sva <= va < sva + rsz: return raw + va - sva
    raise SystemExit(f'VA {va:#x} not in a section')
movz_w0 = lambda imm: 0x52800000 | imm << 5
# (VA, old bank, new bank)
patches = [(0x131c, 5, 6), (0x1340, 5, 6), (0x1360, 5, 6), (0x1380, 5, 6), (0x13a0, 3, 4)]
for va, old, new in patches:
    o = off(va); word = struct.unpack_from('<I', d, o)[0]
    if word == movz_w0(new): continue
    if word != movz_w0(old): raise SystemExit(f'{va:#x}: {word:#010x} is not mov w0,#{old}')
    struct.pack_into('<I', d, o, movz_w0(new))
open(dst, 'wb').write(d)
print(f'patched {len(patches)} GPIO bank IDs -> {dst}')
