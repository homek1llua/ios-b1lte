#!/bin/bash
# Builds Ign1te.app (macOS with Xcode): out/Ign1te.app
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-$here/out}
app="$out/Ign1te.app"
rm -rf "$app" && mkdir -p "$app"
xcrun -sdk iphoneos swiftc -parse-as-library -O -target arm64-apple-ios17.0 "$here/Ign1te.swift" -o "$app/Ign1te"
cp "$here/Info.plist" "$here"/AppIcon*.png "$app/"
plutil -convert binary1 "$app/Info.plist"
codesign -f -s - "$app"
file "$app/Ign1te"; ls -la "$app"
