#!/usr/bin/env bash
# Xcode/SwiftPM compiler artifacts must avoid File Provider FinderInfo injection.
# This is tool cache only; evidence stays in .tmp and deliverables stay in dist.
HOSTSHELF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOSTSHELF_CACHE_KEY="$(printf '%s' "$HOSTSHELF_ROOT" | shasum -a 256 | cut -c 1-12)"
HOSTSHELF_TOOL_CACHE="${TMPDIR:-/tmp}/HostShelf-tools-$HOSTSHELF_CACHE_KEY"
mkdir -p "$HOSTSHELF_TOOL_CACHE" "$HOSTSHELF_ROOT/.tmp/evidence"
