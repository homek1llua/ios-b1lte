#!/usr/bin/env bash
# Build B2L_DEPSROOT for scripts/build-kernel.sh from the pinned Apple open
# source in docs/build.md (macOS with Xcode only):
#   1. AvailabilityVersions -> availability.pl + headers
#   2. XNU exported headers (installhdrs) from the prepared xnu/ tree
#   3. libdispatch libfirehose_kernel.a for iPhoneOS
#
#   KDKROOT=... B2L_DEPSROOT=out/deps build-deps.sh [WORKDIR]
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${KDKROOT:?Set KDKROOT to the installed KDK}"
: "${B2L_DEPSROOT:?Set B2L_DEPSROOT to the output root}"
work="${1:-$repo_root/out/deps-work}"
xnu_path="${XNU_PATH:-$repo_root/xnu}"
mkdir -p "$work" "$B2L_DEPSROOT"
export B2L_DEPSROOT

fetch() { # repo commit dir
  [[ -d "$3/.git" ]] || { git init -q "$3"; git -C "$3" remote add origin "https://github.com/apple-oss-distributions/$1.git"; }
  git -C "$3" fetch -q --depth 1 origin "$2"; git -C "$3" checkout -q --detach -f "$2"
}

echo "== AvailabilityVersions"
fetch AvailabilityVersions 149b1777f3e8c2133042d8e188f72e3adf6a7110 "$work/AvailabilityVersions"
bash "$repo_root/tools/b1l/install-availability.sh" "$work/AvailabilityVersions" "$B2L_DEPSROOT"

echo "== XNU headers"
make -C "$xnu_path" SDKROOT=macosx KDKROOT="$KDKROOT" \
  TARGET_CONFIGS='DEVELOPMENT ARM64 B2L' PLATFORM=iPhoneOS PLATFORM_FOR_CONFIG=iPhoneOS \
  SDKVERSION=26.5 RC_DARWIN_KERNEL_VERSION=25.5.0 \
  OBJROOT="$work/hdr-obj" SYMROOT="$work/hdr-sym" DSTROOT="$B2L_DEPSROOT" installhdrs

echo "== libfirehose_kernel"
# Kernel-mode sources still include TargetConditionals.h; take it from the KDK
# or the macOS SDK's Kernel.framework, after the B2L and KDK private headers.
sdk_kernel_headers="$(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks/Kernel.framework/Headers"
for d in "$KDKROOT/System/Library/Frameworks/Kernel.framework/Versions/A/Headers" "$sdk_kernel_headers"; do
  [[ -f "$d/TargetConditionals.h" ]] && echo "TargetConditionals.h: $d"
done
fetch libdispatch 701f4d1a24ae9c6863901bbbb22624b7d1b87321 "$work/libdispatch"
xcodebuild -project "$work/libdispatch/libdispatch.xcodeproj" -target libfirehose_kernel \
  -configuration Release -sdk iphoneos -arch arm64 \
  OBJROOT="$work/firehose-obj" SYMROOT="$work/firehose-sym" DSTROOT="$B2L_DEPSROOT" CODE_SIGNING_ALLOWED=NO \
  OTHER_CFLAGS='$(inherited) -mcpu=generic -march=armv8-a+crypto' \
  HEADER_SEARCH_PATHS="$B2L_DEPSROOT/usr/local/include/kernel $B2L_DEPSROOT/System/Library/Frameworks/Kernel.framework/PrivateHeaders $B2L_DEPSROOT/System/Library/Frameworks/Kernel.framework/Headers $work/libdispatch $B2L_DEPSROOT/usr/local/include/os $B2L_DEPSROOT/usr/local/include/firehose $KDKROOT/System/Library/Frameworks/Kernel.framework/Versions/A/PrivateHeaders $KDKROOT/System/Library/Frameworks/Kernel.framework/Versions/A/Headers $sdk_kernel_headers" \
  install
lib="$B2L_DEPSROOT/usr/local/lib/kernel"
[[ -f "$lib/libfirehose_kernel.a" ]] || cp "$lib/liblibfirehose_kernel.a" "$lib/libfirehose_kernel.a"
echo "Dependencies ready in $B2L_DEPSROOT"
