#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source script/build_paths.sh
MODE="${1:---preview}"
case "$MODE" in --preview|--developer-id|--signed) ;; *) echo 'usage: package.sh [--preview|--developer-id|--signed]' >&2; exit 2;; esac
if [[ "$MODE" != --preview ]]; then
  : "${HOSTSHELF_SIGN_IDENTITY:?需要 Developer ID Application 身份}"
fi
if [[ "$MODE" == --signed ]]; then
  : "${HOSTSHELF_NOTARY_PROFILE:?需要已保存在 Keychain 的 notarytool profile}"
fi
VERSION="$(sed -n "s/.*MARKETING_VERSION: '\([^']*\)'.*/\1/p" project.yml)"
OUTPUT_DIR="$ROOT_DIR/dist/local-preview"
if [[ "$MODE" == --developer-id ]]; then OUTPUT_DIR="$ROOT_DIR/dist/signed-preview"; fi
if [[ "$MODE" == --signed ]]; then OUTPUT_DIR="$ROOT_DIR/dist/release"; fi
mkdir -p "$OUTPUT_DIR"
for ARCH in arm64 x86_64; do
  ./script/build.sh "$ARCH" Release
  WORK_DIR="$(mktemp -d "$HOSTSHELF_TOOL_CACHE/package-$ARCH.XXXXXX")"
  STAGE="$WORK_DIR/stage"
  mkdir -p "$STAGE"
  trap 'if [[ -n "${WORK_DIR:-}" ]]; then rm -rf "$WORK_DIR"; fi' EXIT
  # File Provider can recreate FinderInfo after cleaning; keep hdiutil staging off it.
  ditto --norsrc --noextattr "$HOSTSHELF_TOOL_CACHE/build-$ARCH-Release/Build/Products/Release/HostShelf.app" "$STAGE/HostShelf.app"
  ln -s /Applications "$STAGE/Applications"
  APP="$STAGE/HostShelf.app"
  python3 script/check_binary_privacy.py "$APP" > "$WORK_DIR/privacy.json"
  SIGN_IDENTITY='-'
  SIGN_OPTIONS=(--force --sign "$SIGN_IDENTITY" --options runtime)
  if [[ "$MODE" != --preview ]]; then
    SIGN_IDENTITY="$HOSTSHELF_SIGN_IDENTITY"
    SIGN_OPTIONS=(--force --sign "$SIGN_IDENTITY" --options runtime --timestamp)
  fi
  codesign "${SIGN_OPTIONS[@]}" "$APP/Contents/Frameworks/HostShelfCore.framework"
  codesign "${SIGN_OPTIONS[@]}" --entitlements Config/HostShelf.entitlements "$APP"
  if [[ "$MODE" == --signed ]]; then
    ZIP="$WORK_DIR/HostShelf.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$HOSTSHELF_NOTARY_PROFILE" --wait \
      --output-format json > "$OUTPUT_DIR/notary-app-$ARCH.json"
    python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("status")=="Accepted" else 1)' "$OUTPUT_DIR/notary-app-$ARCH.json"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
  elif [[ "$MODE" == --preview ]]; then
    cat > "$STAGE/本地试用说明.txt" <<'NOTICE'
本安装包为本地开发试用产物，采用临时签名，未完成 Developer ID 签名与 Apple 公证。
不可将其作为正式发行包传播。Intel 与 macOS 14 运行、首次自动化权限尚需独立验收。
NOTICE
  else
    cat > "$STAGE/签名与验收状态.txt" <<'NOTICE'
签名：Developer ID Application。
Apple 公证：未执行。本包为签名试用候选，尚未作为正式发行版发布。
Intel 原生运行、macOS 14 运行、首次 Terminal 自动化权限：见项目验收记录。
NOTICE
  fi
  DMG="$OUTPUT_DIR/HostShelf-$VERSION-macos-$ARCH.dmg"
  if [[ -e "$DMG" ]]; then echo "安装包已存在，停止覆盖：$DMG" >&2; exit 1; fi
  hdiutil create -volname "HostShelf $ARCH" -srcfolder "$STAGE" -format UDZO "$DMG"
  if [[ "$MODE" != --preview ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  fi
  if [[ "$MODE" == --signed ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$HOSTSHELF_NOTARY_PROFILE" --wait \
      --output-format json > "$OUTPUT_DIR/notary-dmg-$ARCH.json"
    python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("status")=="Accepted" else 1)' "$OUTPUT_DIR/notary-dmg-$ARCH.json"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
  fi
  python3 script/inspect_artifact.py "$APP" "$ARCH" --mode="$MODE" > "$OUTPUT_DIR/artifact-$ARCH.json"
  (
    cd "$OUTPUT_DIR"
    shasum -a 256 "HostShelf-$VERSION-macos-$ARCH.dmg" > "HostShelf-$VERSION-macos-$ARCH.dmg.sha256"
  )
  rm -rf "$WORK_DIR"
  WORK_DIR=''
done
echo "产物目录：$OUTPUT_DIR"
