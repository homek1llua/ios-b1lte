#!/usr/bin/env bash
# Prepare a disposable Mu-Silicium tree for scripts/build-boot-firmware.sh:
# upstream at the commit in docs/project/part-1-overview.md, its submodules,
# native BaseTools and Conf/. Then turn upstream beyond1ltePkg into the B2L
# S10 platform (scripts/make-b1l-platform.sh). Prints the WORKSPACE path.
#
#   setup-silicium-workspace.sh [WORKSPACE]   (default: out/silicium)
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${1:-$repo_root/out/silicium}"
commit=a8ca6f0d63709a55f66e8f68b0356da4a7cc75d5

if [[ ! -d "$workspace/.git" ]]; then
  git init -q "$workspace"
  git -C "$workspace" remote add origin https://github.com/Project-Silicium/Mu-Silicium.git
fi
git -C "$workspace" fetch -q --depth 1 origin "$commit"
git -C "$workspace" checkout -q --detach -f "$commit"
# Binaries (device blobs, ~600 MB) are not used by this platform build.
git -C "$workspace" submodule update -q --init --depth 1 \
  Mu_Basecore Silicium-ACPI Common/Mu Common/Mu_OEM_Sample \
  Silicon/Silicium/OpensslPkg/Library/OpensslLib/openssl >&2
for sub in Mu_Basecore Common/Mu Common/Mu_OEM_Sample; do
  git -C "$workspace/$sub" submodule update -q --init --depth 1 >&2
done
make -s -C "$workspace/Mu_Basecore/BaseTools/Source/C" -j"$(getconf _NPROCESSORS_ONLN)" >&2
mkdir -p "$workspace/Conf"
for name in tools_def target build_rule; do
  [[ -f "$workspace/Conf/$name.txt" ]] || cp "$workspace/Mu_Basecore/BaseTools/Conf/$name.template" "$workspace/Conf/$name.txt"
done
bash "$repo_root/scripts/make-b1l-platform.sh" "$workspace" >&2
echo "$workspace"
