#!/usr/bin/env bash
# Build the iOS 26.6.2 (23G90) USERDATA root and the SYSTEM image on a clean
# macOS machine (CI), with tools/b1l/build-ios-root.sh and build-system-image.sh.
# Prepares what the original work folder had on disk:
#   - the decrypted OS, SystemOS and AppOS images, fetched from Apple's IPSW
#     (only those three members, by HTTP range requests);
#   - nc-static, built from tools/b1l/static-translate;
#   - the translated dyld cache (static-work/out-0250): nc-static apply on the
#     original cache, then the two MediaServices NOPs (docs/journal/build-b1l-0011.md,
#     docs/userdata-clean.md).
# Touches no phone. Run with sudo (the root copy keeps iOS owners).
#
#   sudo -E bash ci-build-ios-images.sh WORKDIR
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo -E" >&2; exit 1; }
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mkdir -p "$1" && cd "$1" && pwd)"
ipsw_url="${IPSW_URL:-https://updates.cdn-apple.com/2026SummerFCS/a1dbd14a-9e9d-49b3-9af6-02286d68883f/iPhone17,2_26.6.2_23G90_Restore.ipsw}"
python="${B2L_PYTHON:-$(command -v python3)}"
ipsw="$work/ipsw-23G90"
nc="$work/nc-static"
cache_src="$work/cache-translated"
cache_orig="$work/cache-orig"
mkdir -p "$ipsw" "$cache_src" "$cache_orig"

echo "== A. IPSW members (OS, SystemOS, AppOS)"
if [[ ! -f "$ipsw/OS.dmg" || ! -f "$ipsw/SystemOS.dmg" || ! -f "$ipsw/AppOS.dmg" ]]; then
  (cd "$ipsw" && remotezip "$ipsw_url" 094-95611-090.dmg.aea 094-96846-092.dmg.aea 094-96441-094.dmg)
  for pair in "094-95611-090:OS" "094-96846-092:SystemOS"; do
    name=${pair%%:*}; dst=${pair##*:}
    head -c 65536 "$ipsw/$name.dmg.aea" > "$ipsw/$name.head"
    key=$("$python" -I "$repo_root/tools/b1l/aea-key.py" "$ipsw/$name.head")
    aea decrypt -i "$ipsw/$name.dmg.aea" -o "$ipsw/$dst.dmg" -key-value "$key"
    rm -f "$ipsw/$name.head" "$ipsw/$name.dmg.aea"
  done
  mv "$ipsw/094-96441-094.dmg" "$ipsw/AppOS.dmg"
fi
ls -la "$ipsw"
df -h "$work" | tail -1

echo "== B. nc-static"
cc -O2 -I "$repo_root/common/cache" -I "$repo_root/xnu-overlay/bsd/kern" -o "$nc" \
  "$repo_root/tools/b1l/static-translate/nc-static.c" "$repo_root"/common/cache/*.c 2>/dev/null
"$nc" 2>&1 | head -1 || true

echo "== C. translated dyld cache"
mnt=$(hdiutil attach -readonly -nobrowse -plist "$ipsw/SystemOS.dmg" |
  grep -A1 '<key>mount-point</key>' | grep -o '<string>.*</string>' | sed 's/<[^>]*>//g' | head -1)
[[ -n "$mnt" ]] || { echo "cannot mount SystemOS.dmg" >&2; exit 1; }
caches=()
for f in "$mnt"/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e*; do
  [[ "$(head -c 7 "$f")" == dyld_v1 ]] || continue
  cp "$f" "$cache_orig/"; caches+=("$cache_orig/$(basename "$f")")
done
hdiutil detach "$mnt" >/dev/null
echo "cache files: ${#caches[@]}"
main="$cache_orig/dyld_shared_cache_arm64e"
[[ -f "$main" ]] || { echo "main cache missing" >&2; exit 1; }
ordered=("$main"); for f in "${caches[@]}"; do [[ "$f" == "$main" ]] || ordered+=("$f"); done
"$nc" apply "$cache_src" "${ordered[@]}"
translated=("$cache_src/dyld_shared_cache_arm64e"); for f in "${ordered[@]:1}"; do translated+=("$cache_src/$(basename "$f")"); done
"$nc" nop-call "${translated[@]}" -- 0x1ae8593f8 0x1b2571fe0
"$nc" nop-call "${translated[@]}" -- 0x1ae85d7f0 0x1b2571ff0

echo "== D. iOS root (tools/b1l/build-ios-root.sh)"
B2L_IPSW_DIR="$ipsw" B2L_TOOLS="$repo_root/tools/b1l" B2L_ROOT="$repo_root" B2L_PYTHON="$python" \
B2L_OUT="$work/out" B2L_CACHE_SRC="$cache_src" B2L_CACHE_ORIG="$cache_orig" B2L_NC_STATIC="$nc" \
  bash "$repo_root/tools/b1l/build-ios-root.sh"
rm -rf "$cache_src" "$cache_orig"

echo "== E. SYSTEM image (tools/b1l/build-system-image.sh)"
B2L_ROOT="$repo_root" B2L_PYTHON="$python" B2L_ROOT_IMAGE="$work/out/ios26-userdata.hfs.img" \
B2L_SYSTEM_OUT="$work/system" bash "$repo_root/tools/b1l/build-system-image.sh"
ls -la "$work/out" "$work/system"
