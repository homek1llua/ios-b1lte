#!/usr/bin/env bash
# Rebuild an external, disposable beyond2lte firmware tree with the XNU app.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${WORKSPACE:?Set WORKSPACE to the disposable prepared Mu-Silicium tree}"
"$repo_root/scripts/build-efi.sh"
loader="$WORKSPACE/Build/B2LXnu/RELEASE_CLANGPDB/AARCH64/XnuLoader.efi"
board="${B2L_BOARD:-beyond2lte}"
export B2L_BOARD="$board"
touch_options=()
if [[ "${B2L_ENABLE_TOUCH:-0}" == 1 ]]; then touch_options+=(--enable-touch); fi
# Expand safely when the array is empty under bash 3.2's set -u.
"${PYTHON_COMMAND:-python3}" "$repo_root/scripts/prepare-boot-firmware.py" \
  --mu "$WORKSPACE" --loader "$loader" \
  --loader-guid 92742D9E-1A4F-42F8-9DC9-53895297B2F4 ${touch_options[@]+"${touch_options[@]}"}
export PACKAGES_PATH="$WORKSPACE/Platforms/Samsung:$WORKSPACE/Common/Mu:$WORKSPACE/Common/Mu_OEM_Sample:$WORKSPACE/Silicon/Samsung:$WORKSPACE/Silicon/Silicium${PACKAGES_PATH:+:$PACKAGES_PATH}"
# DSC build-time ACPI declarations remain external. Their firmware-volume
# inclusion is disabled by the XNU profile; XNU uses an Apple device tree.
# Silicium-ACPI renamed SoCs/ to Silicon/; accept either layout.
acpi_soc="$WORKSPACE/Silicium-ACPI/Silicon/Samsung"
[[ -d "$acpi_soc" ]] || acpi_soc="$WORKSPACE/Silicium-ACPI/SoCs/Samsung"
export PACKAGES_PATH="$PACKAGES_PATH:$WORKSPACE/Silicium-ACPI:$WORKSPACE/Silicium-ACPI/Platforms/Samsung:$acpi_soc"
export DSC_PATH="${board}Pkg/${board}.dsc"
exec "$repo_root/scripts/build-efi.sh" \
  -D FD_BASE=0xC9000000 -D FD_SIZE=0x400000 -D FD_BLOCKS=0x400 \
  -D ENABLE_SECUREBOOT=0 -D DEVICE_MODEL=0 "$@"
