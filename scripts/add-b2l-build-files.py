#!/usr/bin/env python3
"""Add overlay sources that no committed patch lists to XNU's conf/files.

Patches 0104 and 0107 are hand-written notes without hunk positions, so
git apply refuses them; their entries are added here together with sources
the kernel references but no patch listed (B1L logs used a local tree).
Idempotent; appends after the last existing B2L entry of each file.
"""
import sys
from pathlib import Path

ENTRIES = {
    "bsd/conf/files": [
        "bsd/dev/b2l_mali_core.c\t\t\toptional b2l",                      # 0104
        "bsd/dev/b2l_hakios_net.c\t\t\toptional b2l",                     # Wi-Fi: en0 (B1L-0152)
        "bsd/dev/b2l_hakios_sta.c\t\t\toptional b2l",                     # Wi-Fi: station
        "bsd/dev/b2l_hakios_apple80211.c\t\toptional b2l",                # Wi-Fi: wifid ioctls
    ],
    "iokit/conf/files": [
        "iokit/Kernel/arm/B2LMaliService.cpp optional iokitcpp b2l",       # 0104
        "iokit/Kernel/arm/B2LMetalAccel.cpp optional iokitcpp b2l",        # 0107
        "iokit/Kernel/arm/B2LBluetooth.cpp optional iokitcpp b2l",         # b2l_bt_fetch
        "iokit/Kernel/arm/B2LWifi.cpp optional iokitcpp b2l",              # BCM4375 PCIe (B1L-0149+)
        "iokit/Kernel/arm/B2LHakiosWLAN.cpp optional iokitcpp b2l",        # IO80211 registry for wifid
    ],
    "osfmk/conf/files": [
        "osfmk/arm64/b2l_prof.c optional b2l",                             # b2l_prof_start
        "osfmk/corecrypto/b2l_ccsha1_ltc.c optional b2l",                  # ccsha1_ltc_di
    ],
}


# IOKit personalities no committed patch adds. B2LWifi is started like B2LInput (0040).
PERSONALITIES = [
    "    \"   {'IOClass'=B2LWifi;'IOProviderClass'=IOResources;'IOMatchCategory'=B2LWifi;},\"",
]
ANCHOR = "    \"   {'IOClass'=B2LInput;'IOProviderClass'=IOResources;'IOMatchCategory'=B2LInput;},\""


def add_personalities(xnu):
    path = xnu / "iokit/KernelConfigTables.cpp"
    rows = path.read_text().splitlines()
    if rows.count(ANCHOR) != 1:
        raise SystemExit("KernelConfigTables.cpp: expected one B2LInput personality")
    missing = [p for p in PERSONALITIES if p not in rows]
    if missing:
        i = rows.index(ANCHOR)
        rows[i + 1:i + 1] = missing
        path.write_text("\n".join(rows) + "\n")
        for p in missing:
            print(f"KernelConfigTables.cpp: + {p.split('=')[1].split(';')[0]}")


def main():
    xnu = Path(sys.argv[1])
    add_personalities(xnu)
    for conf, lines in ENTRIES.items():
        path = xnu / conf
        text = path.read_text()
        existing = {l.split()[0] for l in text.splitlines() if l.strip() and not l.startswith("#")}
        missing = [l for l in lines if l.split()[0] not in existing]
        for line in missing:
            source = xnu / line.split()[0]
            if not source.is_file():
                raise SystemExit(f"missing overlay source {source}")
        if not missing:
            continue
        rows = text.splitlines()
        last = max(i for i, l in enumerate(rows) if "optional" in l and "b2l" in l.split())
        rows[last + 1:last + 1] = missing
        path.write_text("\n".join(rows) + "\n")
        for line in missing:
            print(f"{conf}: + {line.split()[0]}")


if __name__ == "__main__":
    main()
