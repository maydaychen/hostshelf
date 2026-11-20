#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
for ARCH in arm64 x86_64; do
  ./script/build.sh "$ARCH" Release
done
