#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source script/build_paths.sh
ARCH="${1:-$(uname -m)}"
CONFIGURATION="${2:-Debug}"
case "$ARCH" in arm64|x86_64) ;; *) echo '架构只能是 arm64 或 x86_64' >&2; exit 2;; esac
case "$CONFIGURATION" in Debug|Release) ;; *) echo '配置只能是 Debug 或 Release' >&2; exit 2;; esac
BUILD_SETTINGS=("ARCHS=$ARCH" ONLY_ACTIVE_ARCH=NO)
if [[ "$CONFIGURATION" == Release ]]; then
  SOURCE_ROOT_PHYSICAL="$(cd "$ROOT_DIR" && pwd -P)"
  BUILD_ROOT_LOGICAL="$(cd "$HOSTSHELF_TOOL_CACHE" && pwd -L)"
  BUILD_ROOT_PHYSICAL="$(cd "$HOSTSHELF_TOOL_CACHE" && pwd -P)"
  SWIFT_FLAGS='$(inherited)'
  C_FLAGS='$(inherited)'
  for MAPPING in "$ROOT_DIR=/HostShelf" "$SOURCE_ROOT_PHYSICAL=/HostShelf" \
      "$BUILD_ROOT_LOGICAL=/HostShelfBuild" "$BUILD_ROOT_PHYSICAL=/HostShelfBuild"; do
    SWIFT_FLAGS+=" -file-prefix-map \"$MAPPING\" -debug-prefix-map \"$MAPPING\""
    C_FLAGS+=" \"-ffile-prefix-map=$MAPPING\""
  done
  BUILD_SETTINGS+=("OTHER_SWIFT_FLAGS=$SWIFT_FLAGS" "OTHER_CFLAGS=$C_FLAGS")
fi
xcodegen generate
xcodebuild -project HostShelf.xcodeproj -scheme HostShelf -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' -derivedDataPath "$HOSTSHELF_TOOL_CACHE/build-$ARCH-$CONFIGURATION" \
  "${BUILD_SETTINGS[@]}" build
if [[ "$CONFIGURATION" == Release ]]; then
  python3 script/check_binary_privacy.py \
    "$HOSTSHELF_TOOL_CACHE/build-$ARCH-Release/Build/Products/Release/HostShelf.app"
fi
