#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source script/build_paths.sh
MODE="${1:---anonymous}"
case "$MODE" in
  --anonymous) DEFAULT_DIR=dist/release ;;
  --developer-id) DEFAULT_DIR=dist/signed-preview ;;
  --preview) DEFAULT_DIR=dist/local-preview ;;
  --signed) DEFAULT_DIR=dist/release ;;
  *) echo 'usage: verify_packages.sh [--anonymous|--developer-id|--preview|--signed] [directory]' >&2; exit 2 ;;
esac
OUTPUT_DIR="${2:-$DEFAULT_DIR}"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
VERSION="$(sed -n "s/.*MARKETING_VERSION: '\([^']*\)'.*/\1/p" project.yml)"
for ARCH in arm64 x86_64; do
  NAME="HostShelf-$VERSION-macos-$ARCH.dmg"
  DMG="$OUTPUT_DIR/$NAME"
  (
    cd "$OUTPUT_DIR"
    shasum -a 256 --check "$NAME.sha256"
  )
  if [[ "$MODE" == --anonymous || "$MODE" == --preview ]]; then
    if dmg_sig="$(codesign -dv "$DMG" 2>&1)"; then
      echo "匿名/试用 DMG 不得包含外层签名：$DMG" >&2
      exit 1
    fi
    if ! grep -q "code object is not signed at all" <<< "$dmg_sig"; then
      echo "外层 DMG 签名检查出现意外输出：$dmg_sig" >&2
      exit 1
    fi
  else
    codesign --verify --strict "$DMG"
  fi
  hdiutil verify "$DMG"
  MOUNT="$(mktemp -d "$HOSTSHELF_TOOL_CACHE/verify-$ARCH.XXXXXX")"
  trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; rmdir "$MOUNT" 2>/dev/null || true' EXIT
  hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG"
  python3 script/inspect_artifact.py "$MOUNT/HostShelf.app" "$ARCH" --mode="$MODE" > "$OUTPUT_DIR/artifact-$ARCH.json"
  hdiutil detach "$MOUNT"
  rmdir "$MOUNT"
  trap - EXIT
done
