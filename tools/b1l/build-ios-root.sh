#!/bin/bash
# Build the 32 GiB case-sensitive Journaled HFS+ iOS 26 root for the S10 port,
# following beyond2lte-ios/docs/ios-userspace-root.md. Run with sudo:
#
#   sudo bash build-ios-root.sh
#
# Reads the decrypted 23G90 images in ~/Developer/s10-port/ipsw-23G90 and writes
# beyond2lte-ios/out/ipsw/ios26-userdata.hfs.img. Touches no phone.
# Every location can be overridden (S10_PORT, B2L_IPSW_DIR, B2L_TOOLS, B2L_ROOT,
# B2L_PYTHON, B2L_OUT, B2L_CACHE_SRC, B2L_CACHE_ORIG, B2L_NC_STATIC); see
# scripts/ci-build-ios-images.sh.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
user_home=$(eval echo "~${SUDO_USER:-$USER}")
port="${S10_PORT:-$user_home/Developer/s10-port}"
ipsw="${B2L_IPSW_DIR:-$port/ipsw-23G90}"
tools="${B2L_TOOLS:-$port/b1l-tools}"
repo="${B2L_ROOT:-$port/beyond2lte-ios}"
python="${B2L_PYTHON:-$user_home/Developer/tools/mamba/envs/s10/bin/python3}"
out="${B2L_OUT:-$repo/out/ipsw}"
image="$out/ios26-userdata.hfs.img"
log="$out/build-ios-root.log"

mkdir -p "$out"
# B1L-0250: an earlier image is kept, renamed with its date (nothing is deleted).
if [[ -e "$image" ]]; then
  old="$image.before-$(date -r "$image" +%Y%m%d-%H%M)"
  [[ ! -e "$old" ]] || { echo "$old already exists; move it away first" >&2; exit 1; }
  mv "$image" "$old"
  [[ ! -e "$image.sha256" ]] || mv "$image.sha256" "$old.sha256"
  echo "earlier image kept as $old"
fi
exec > >(tee "$log") 2>&1

echo "== 0/7 decrypted IPSW images"
if [[ ! -f "$ipsw/OS.dmg" || ! -f "$ipsw/SystemOS.dmg" || ! -f "$ipsw/AppOS.dmg" ]]; then
  src="$user_home/Downloads/iPhone17,2_26.6.2_23G90_Restore.ipsw"
  [[ -f "$src" ]] || { echo "missing $src" >&2; exit 1; }
  mkdir -p "$ipsw"
  unzip -o -q "$src" 094-95611-090.dmg.aea 094-96846-092.dmg.aea 094-96441-094.dmg -d "$ipsw"
  for pair in "094-95611-090:OS" "094-96846-092:SystemOS"; do
    name=${pair%%:*}; dst=${pair##*:}
    head -c 65536 "$ipsw/$name.dmg.aea" > "$ipsw/$name.head"
    key=$("$python" -I "$tools/aea-key.py" "$ipsw/$name.head")
    aea decrypt -i "$ipsw/$name.dmg.aea" -o "$ipsw/$dst.dmg" -key-value "$key"
    rm -f "$ipsw/$name.head"
  done
  mv "$ipsw/094-96441-094.dmg" "$ipsw/AppOS.dmg"
  chown -R "${SUDO_USER:-root}" "$ipsw"
fi
ls -la "$ipsw"/OS.dmg "$ipsw"/SystemOS.dmg "$ipsw"/AppOS.dmg

attached=()
cleanup() {
  # Clean unmount first so the HFS journal is closed; force only as a fallback.
  for m in "${attached[@]:-}"; do
    [[ -n "$m" ]] || continue
    hdiutil detach "$m" >/dev/null 2>&1 || hdiutil detach -force "$m" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

# attach IMAGE [options...] -> prints the mount point. Runs in $(...), so the
# caller records the mount point for cleanup.
attach() {
  local mnt
  mnt=$(hdiutil attach -plist -nobrowse -owners on "$@" |
    grep -A1 '<key>mount-point</key>' | grep -o '<string>.*</string>' | sed 's/<[^>]*>//g' | head -1)
  [[ -n "$mnt" ]] || { echo "attach failed: $*" >&2; exit 1; }
  echo "$mnt"
}

echo "== 1/7 create raw 32 GiB case-sensitive Journaled HFS+"
hdiutil create -size 32g -layout NONE -fs "Case-sensitive Journaled HFS+" \
  -volname B2LIOSROOT -type UDTO -o "$out/ios26-userdata.hfs"
mv "$out/ios26-userdata.hfs.cdr" "$image"
chown "${SUDO_USER:-root}" "$image"

echo "== 2/7 attach images"
root=$(attach -readwrite -imagekey diskimage-class=CRawDiskImage "$image"); attached+=("$root")
os=$(attach -readonly "$ipsw/OS.dmg"); attached+=("$os")
sysos=$(attach -readonly "$ipsw/SystemOS.dmg"); attached+=("$sysos")
appos=$(attach -readonly "$ipsw/AppOS.dmg"); attached+=("$appos")
echo "root=$root os=$os systemos=$sysos appos=$appos"
mdutil -i off "$root" >/dev/null 2>&1 || true   # no Spotlight index written into the iOS root
[[ -x "$os/sbin/launchd" && -d "$sysos/System/Library/Caches/com.apple.dyld" ]] || {
  echo "unexpected source layout" >&2; exit 1; }

echo "== 3/7 copy OS"
"$python" -I "$tools/copy-tree.py" "$os" "$root" --report "$out/copy-os.json"
echo "== 4/7 copy cryptexes"
mkdir -p "$root/private/preboot/Cryptexes"
"$python" -I "$tools/copy-tree.py" "$sysos" "$root/private/preboot/Cryptexes/OS" --report "$out/copy-systemos.json"
"$python" -I "$tools/copy-tree.py" "$appos" "$root/private/preboot/Cryptexes/App" --report "$out/copy-appos.json"

echo "== 5/7 prepare-ios-root.py (dry run, apply, verify)"
"$python" -I "$repo/scripts/prepare-ios-root.py" "$root" --dry-run
"$python" -I "$repo/scripts/prepare-ios-root.py" "$root" --report "$out/prepare-report.json"
"$python" -I "$repo/scripts/prepare-ios-root.py" "$root" --verify

echo "== 5b/7 PAC translation (as B1L-0011/0012 did on the old root)"
# static-work/out-0250: the original cache translated by nc-static apply (PACGA ABI v2, stub islands; corecrypto
# excluded) plus the two MediaServices NOPs (B1L-0011); compared with static-work/orig: 2 unexpected changes, both
# those NOPs (static-work/compare-0250.txt). Written in place: same size, inode and owner.
cache_src="${B2L_CACHE_SRC:-$port/static-work/out-0250}"
cache_orig="${B2L_CACHE_ORIG:-$port/static-work/orig}"
nc="${B2L_NC_STATIC:-$tools/static-translate/nc-static}"
rel=private/preboot/Cryptexes/OS/System/Library/Caches/com.apple.dyld
[[ -d "$cache_src" && -d "$cache_orig" && -x "$nc" ]] || { echo "missing out-0250, orig or nc-static" >&2; exit 1; }
n=0
for f in "$cache_src"/dyld_shared_cache_arm64e*; do
  name=$(basename "$f"); dst="$root/$rel/$name"
  [[ -f "$dst" ]] || { echo "missing target $name" >&2; exit 1; }
  cmp -s "$cache_orig/$name" "$dst" || { echo "$name in the image is not the original cache" >&2; exit 1; }
  meta=$(stat -f '%u:%g %Lp %i' "$dst")
  dd if="$f" of="$dst" bs=4m conv=notrunc 2>/dev/null
  cmp -s "$f" "$dst" || { echo "verify failed: $name" >&2; exit 1; }
  [[ $(stat -f '%u:%g %Lp %i' "$dst") == "$meta" ]] || { echo "metadata changed: $name" >&2; exit 1; }
  n=$((n + 1))
done
echo "cache files translated: $n"
echo "standalone arm64e Mach-O files (outside the cache and /private/var, plus the 50 staged apps the kernel"
echo "moves to /Applications, B1L-0018/0024), in place"
macho_files() {
  find "$root" -xdev -type f -size +8k ! -path '*/com.apple.dyld/*' ! -path "$root/private/var/*" -print0
  find "$root/private/var/staged_system_apps" -xdev -type f -size +8k -print0
}
macho_files | xargs -0 "$nc" macho-apply | awk '/^macho-apply|^MACHO|^  /' | sort | uniq -c | sort -rn | head -20
echo "check: no convertible words left"
macho_files | xargs -0 "$nc" macho 2>/dev/null | grep -E 'MACHO TOTAL' | sort | uniq -c

echo "== 6/7 unmount and fsck"
sync
cleanup; attached=()
dev=$(hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage "$image" | awk 'NR==1{print $1}')
attached+=("$dev")
fsck_hfs -fn "$dev"
cleanup; attached=()

echo "== 7/7 hash"
shasum -a 256 "$image" | tee "$out/ios26-userdata.hfs.img.sha256"
echo "done: $image"
