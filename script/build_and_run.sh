#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source script/build_paths.sh
MODE="${1:-run}"
case "$MODE" in run|--debug|--logs|--telemetry|--verify) ;; *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2;; esac
ARCH="$(uname -m)"
APP_BINARY="$HOSTSHELF_TOOL_CACHE/build-$ARCH-Debug/Build/Products/Debug/HostShelf.app/Contents/MacOS/HostShelf"
if pgrep -x HostShelf >/dev/null; then pkill -x HostShelf; fi
./script/build.sh "$ARCH" Debug
APP_BUNDLE="$HOSTSHELF_TOOL_CACHE/build-$ARCH-Debug/Build/Products/Debug/HostShelf.app"
case "$MODE" in
  --debug) lldb -- "$APP_BINARY" ;;
  --logs|--telemetry)
    /usr/bin/open "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "HostShelf"'
    ;;
  --verify)
    /usr/bin/open "$APP_BUNDLE"
    sleep 1
    pgrep -x HostShelf >/dev/null
    ;;
  run) /usr/bin/open "$APP_BUNDLE" ;;
esac
