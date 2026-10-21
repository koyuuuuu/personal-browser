#!/usr/bin/env python3
"""Create an original opaque compass app icon using Python's standard library."""
import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def main():
    size = 1024
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            gradient = (x + y) / (2 * size)
            color = (int(20 - 12 * gradient), int(166 - 75 * gradient), int(231 - 45 * gradient))
            dx, dy = x - 511.5, y - 511.5
            radius = math.hypot(dx, dy)
            if 265 <= radius <= 290:
                color = (239, 252, 255)
            # Two triangles form a compass needle on a diagonal axis.
            along = (dx - dy) / math.sqrt(2)
            across = (dx + dy) / math.sqrt(2)
            if abs(along) <= 215 and abs(across) <= (1 - abs(along) / 215) * 88:
                color = (255, 255, 255) if along > 0 else (126, 222, 244)
            rows.extend(color)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">2I5B", size, size, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
    assets = ROOT / "App/Assets.xcassets"
    icon = assets / "AppIcon.appiconset"
    icon.mkdir(parents=True, exist_ok=True)
    (icon / "AppIcon.png").write_bytes(png)
    for path, value in [(assets / "Contents.json", {"info": {"author": "xcode", "version": 1}}),
                        (icon / "Contents.json", {"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}})]:
        path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    print("Generated original 1024px app icon.")


if __name__ == "__main__":
    main()
