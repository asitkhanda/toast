#!/usr/bin/env python3
"""Generate Windows Toast.ico + status tray icons from the shared Mac/web brand art."""
from __future__ import annotations

import io
import struct
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Install Pillow first: pip install Pillow", file=sys.stderr)
    raise SystemExit(1)

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "web" / "public" / "toast_logo.png"
OUT = Path(__file__).resolve().parents[1] / "src" / "Toast" / "Assets"


def png_bytes(im: Image.Image) -> bytes:
    buf = io.BytesIO()
    im.save(buf, format="PNG")
    return buf.getvalue()


def write_ico(path: Path, images: list[Image.Image]) -> None:
    entries = []
    for im in images:
        data = png_bytes(im)
        w, h = im.size
        entries.append((0 if w >= 256 else w, 0 if h >= 256 else h, data))

    offset = 6 + len(entries) * 16
    header = struct.pack("<HHH", 0, 1, len(entries))
    directory = b""
    blobs = b""
    for w, h, data in entries:
        directory += struct.pack("<BBBBHHII", w, h, 0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)
    path.write_bytes(header + directory + blobs)
    print(f"wrote {path.name} ({len(entries)} sizes, {path.stat().st_size} bytes)")


def tray_with_dot(base: Image.Image, rgb: tuple[int, int, int], sizes=(16, 32, 48)) -> list[Image.Image]:
    frames = []
    for s in sizes:
        overlay = base.resize((s, s), Image.Resampling.LANCZOS)
        draw = ImageDraw.Draw(overlay)
        r = max(3, s // 5)
        margin = max(1, s // 16)
        cx = s - r - margin
        cy = s - r - margin
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, 255))
        inner = max(1, r - max(1, s // 16))
        draw.ellipse((cx - inner, cy - inner, cx + inner, cy + inner), fill=(*rgb, 255))
        frames.append(overlay)
    return frames


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"Missing source art: {SRC}")
    OUT.mkdir(parents=True, exist_ok=True)
    img = Image.open(SRC).convert("RGBA")
    write_ico(OUT / "Toast.ico", [img.resize((s, s), Image.Resampling.LANCZOS) for s in (16, 24, 32, 48, 64, 128, 256)])
    write_ico(OUT / "Tray-Default.ico", [img.resize((s, s), Image.Resampling.LANCZOS) for s in (16, 32, 48)])
    for name, rgb in {
        "Ready": (52, 199, 89),
        "Building": (0, 122, 255),
        "Error": (255, 59, 48),
        "Disconnected": (255, 149, 0),
        "Idle": (142, 142, 147),
    }.items():
        write_ico(OUT / f"Tray-{name}.ico", tray_with_dot(img, rgb))


if __name__ == "__main__":
    main()
