#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source script/build_paths.sh
work_dir="$(mktemp -d "$HOSTSHELF_TOOL_CACHE/terminal-launcher.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p .tmp/terminal-launcher-check
xcrun swiftc -swift-version 5 -module-cache-path "$work_dir/module-cache" \
    -emit-module -emit-library -module-name HostShelfCore Sources/HostShelfCore/*.swift \
    -emit-module-path "$work_dir/HostShelfCore.swiftmodule" -o "$work_dir/libHostShelfCore.dylib"
xcrun swiftc -swift-version 5 -D DEBUG -module-cache-path "$work_dir/module-cache" \
    -parse-as-library -I "$work_dir" -L "$work_dir" -lHostShelfCore \
    -Xlinker -rpath -Xlinker "$work_dir" \
    Sources/HostShelf/Services/TerminalLauncher.swift Sources/HostShelf/Services/ExternalActionLauncher.swift \
    Sources/HostShelf/Stores/AppStore.swift Sources/HostShelf/Stores/AppStore+Actions.swift \
    Tests/ServiceChecks/TerminalLauncherCheck.swift -o "$work_dir/terminal-launcher-check"
"$work_dir/terminal-launcher-check" 2>&1 | tee .tmp/terminal-launcher-check/check.log
