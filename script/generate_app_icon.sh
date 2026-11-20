#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/Design/AppIcon-master.png"
OUTPUT="$ROOT_DIR/Sources/HostShelf/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$OUTPUT"
for SIZE in 16 32 128 256 512; do
  for SCALE in 1 2; do
    PIXELS=$((SIZE * SCALE))
    sips --resampleHeightWidth "$PIXELS" "$PIXELS" "$SOURCE" \
      --out "$OUTPUT/icon_${SIZE}x${SIZE}@${SCALE}x.png" >/dev/null
  done
done
python3 - "$OUTPUT" <<'PY'
import json
import sys
from pathlib import Path

output = Path(sys.argv[1])
images = [
    {"filename": f"icon_{size}x{size}@{scale}x.png", "idiom": "mac",
     "scale": f"{scale}x", "size": f"{size}x{size}"}
    for size in (16, 32, 128, 256, 512) for scale in (1, 2)
]
(output / "Contents.json").write_text(
    json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
)
PY
echo "AppIcon 已从原图生成 10 个 macOS 尺寸资源。"
