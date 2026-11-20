#!/usr/bin/env python3
"""Fix the GPIO bank IDs in the owner's 9820 HsI2cDxe binary for upstream GpioDxe.

Same A = 0 vs BANK_ID_A = 1 mismatch as patch-ufs-gpio-banks.py. HsI2cDxe keeps a
28-byte-per-bus table in .data (VA 0x77F0, buses 0-10); each entry is
{Function, SdaBankId, SclBankId, SdaBankNum, SclBankNum, SdaPin, SclPin, ..., Initialized}
and InitBus passes SdaBankId/SclBankId straight to GPIO SetFunction. Buses 4-10 use
bank 15 (GPP in the old numbering), which upstream calls 16 (BANK_ID_P).

  patch-hsi2c-gpio-banks.py IN.efi OUT.efi
"""
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
d = bytearray(open(src, 'rb').read())
pe = struct.unpack_from('<I', d, 0x3c)[0]
nsec = struct.unpack_from('<H', d, pe + 6)[0]; opt = struct.unpack_from('<H', d, pe + 20)[0]
secs = []
for i in range(nsec):
    o = pe + 24 + opt + i * 40
    vsz, va, rsz, raw = struct.unpack_from('<IIII', d, o + 8)
    secs.append((va, rsz, raw))
def off(va):
    for sva, rsz, raw in secs:
        if sva <= va < sva + rsz: return raw + va - sva
    raise SystemExit(f'VA {va:#x} not in a section')
TABLE, SIZE, COUNT, OLD, NEW = 0x77F0, 28, 11, 15, 16
n = 0
for bus in range(COUNT):
    e = off(TABLE + bus * SIZE)
    if not any(d[e:e + SIZE]): continue          # unused bus
    for field in (4, 8):
        v = struct.unpack_from('<I', d, e + field)[0]
        if v == NEW: continue
        if v != OLD: raise SystemExit(f'bus {bus} +{field}: bank {v} != {OLD}')
        struct.pack_into('<I', d, e + field, NEW); n += 1
open(dst, 'wb').write(d)
print(f'patched {n} GPIO bank IDs -> {dst}')
