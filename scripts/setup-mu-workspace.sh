#!/usr/bin/env bash
# Prepare a minimal Mu/EDK II workspace for scripts/build-efi.sh (CI or a clean machine):
# Mu Basecore at the commit documented in docs/build.md, the submodules the B2LXnuPkg build
# needs, native BaseTools and the Conf/ files. Prints the WORKSPACE path.
#
#   setup-mu-workspace.sh [WORKSPACE]   (default: out/mu-workspace)
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${1:-$repo_root/out/mu-workspace}"
mu_commit=762a65dad79e2934cddbefa467b7e2c7b5ee4bc0
basecore="$workspace/Mu_Basecore"

if [[ ! -d "$basecore/.git" ]]; then
  git init -q "$basecore"
  git -C "$basecore" remote add origin https://github.com/microsoft/mu_basecore.git
fi
git -C "$basecore" fetch -q --depth 1 origin "$mu_commit"
git -C "$basecore" checkout -q --detach "$mu_commit"
git -C "$basecore" submodule update -q --init --depth 1 \
  BaseTools/Source/C/BrotliCompress/brotli \
  MdeModulePkg/Library/BrotliCustomDecompressLib/brotli \
  MdePkg/Library/MipiSysTLib/mipisyst

make -s -C "$basecore/BaseTools/Source/C" -j"$(getconf _NPROCESSORS_ONLN)" >&2

mkdir -p "$workspace/Conf"
for name in tools_def target build_rule; do
  [[ -f "$workspace/Conf/$name.txt" ]] || cp "$basecore/BaseTools/Conf/$name.template" "$workspace/Conf/$name.txt"
done
echo "$workspace"
