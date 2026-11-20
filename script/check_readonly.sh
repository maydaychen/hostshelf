#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source script/build_paths.sh
xcrun swiftc -target "$(uname -m)-apple-macos14.0" -module-cache-path "$HOSTSHELF_TOOL_CACHE/readonly-modules" \
  Sources/HostShelfCore/*.swift Tests/ServiceChecks/ReadOnlyIndexCheck.swift -o "$HOSTSHELF_TOOL_CACHE/readonly-check"
"$HOSTSHELF_TOOL_CACHE/readonly-check" "$@"
