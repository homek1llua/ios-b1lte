#!/usr/bin/env bash
# Fetch the original launch cache (/System/Library/xpc/launchd.plist) from the public
# 23G90 IPSW without a local ios26-userdata.hfs.img (for CI). macOS only (aea, hdiutil).
# Downloads just the OS image out of the IPSW zip (HTTP range requests), decrypts it with
# the key Apple publishes (tools/b1l/aea-key.py), copies one file and deletes the rest.
#
#   fetch-ipsw-launch-cache.sh [OUTPUT]   (default: out/ipsw/launchd.plist)
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$repo_root/out/ipsw/launchd.plist}"
ipsw_url="${IPSW_URL:-https://updates.cdn-apple.com/2026SummerFCS/a1dbd14a-9e9d-49b3-9af6-02286d68883f/iPhone17,2_26.6.2_23G90_Restore.ipsw}"
os_member=094-95611-090.dmg.aea   # the OS image, as in tools/b1l/build-ios-root.sh
python="${PYTHON:-python3}"

if [[ -f "$output" ]]; then echo "Launch cache already present: $output"; exit 0; fi
work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/b2l-ipsw.XXXXXX")"
mount_point=""
cleanup() {
  [[ -z "$mount_point" ]] || hdiutil detach "$mount_point" >/dev/null 2>&1 || hdiutil detach -force "$mount_point" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

df -h "$work" | tail -1
echo "Downloading $os_member from $ipsw_url"
(cd "$work" && remotezip "$ipsw_url" "$os_member")

head -c 65536 "$work/$os_member" > "$work/os.head"
key="$("$python" -I "$repo_root/tools/b1l/aea-key.py" "$work/os.head")"
aea decrypt -i "$work/$os_member" -o "$work/OS.dmg" -key-value "$key"
rm -f "$work/$os_member"

mount_point="$(hdiutil attach -readonly -nobrowse -plist "$work/OS.dmg" |
  grep -A1 '<key>mount-point</key>' | grep -o '<string>.*</string>' | sed 's/<[^>]*>//g' | head -1)"
[[ -n "$mount_point" ]] || { echo "Could not mount OS.dmg" >&2; exit 1; }
source_file="$mount_point/System/Library/xpc/launchd.plist"
[[ -f "$source_file" ]] || { echo "Missing $source_file" >&2; exit 1; }
mkdir -p "$(dirname "$output")"
cp "$source_file" "$output"
echo "Launch cache: $output ($(wc -c < "$output" | tr -d ' ') bytes, sha256 $(shasum -a 256 "$output" | cut -d' ' -f1))"
