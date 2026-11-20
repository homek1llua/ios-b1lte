#!/usr/bin/env bash
# Install a Kernel Debug Kit .dmg (KDK.pkg and, if present, KDK_SDK.pkg) and
# print its root, e.g. /Library/Developer/KDKs/KDK_26.5_25F71.kdk. macOS, sudo.
set -euo pipefail
dmg="$1"
mnt="$(mktemp -d)"
hdiutil attach -readonly -nobrowse -mountpoint "$mnt" "$dmg" >/dev/null
trap 'hdiutil detach "$mnt" >/dev/null 2>&1 || true' EXIT
ls -la "$mnt" >&2
for pkg in "$mnt"/*.pkg; do
  echo "Installing $(basename "$pkg")" >&2
  sudo installer -pkg "$pkg" -target / >&2
done
kdk="$(ls -d /Library/Developer/KDKs/KDK_*25F71*.kdk | head -1)"
[[ -d "$kdk/System/Library/Frameworks/Kernel.framework" ]] || { echo "KDK not found after install" >&2; exit 1; }
echo "$kdk"
