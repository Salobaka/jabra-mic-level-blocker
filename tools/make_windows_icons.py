#!/usr/bin/env python3
"""Generate tray icon .ico files for the Windows port (stdlib only).

Outputs windows/assets/{icon_locked,icon_locked_dim,icon_unlocked}.ico
Each file contains 16x16 and 32x32 (2x nearest-neighbor) images, 32bpp BGRA.
"""

import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(os.path.dirname(HERE), "windows", "assets")

# 16x16 pixel-art microphone. '.' transparent, A outline, B body fill, S stand.
MIC = [
    "................",
    ".....AAAA.......",
    "....ABBBBA......",
    "....ABBBBA......",
    "....ABBBBA......",
    "....ABBBBA......",
    "....ABBBBA......",
    "....AAAAAA......",
    "..SS......SS....",
    ".SS........SS...",
    ".SS...SS...SS...",
    ".SS...SS...SS...",
    "..SS..SS..SS....",
    "...SSSSSSSS.....",
    ".....AAAA.......",
    "................",
]

PALETTES = {
    "icon_locked": {  # bright orange
        "A": (0xB2, 0x5E, 0x00, 0xFF),
        "B": (0xFF, 0x95, 0x00, 0xFF),
        "S": (0xB2, 0x5E, 0x00, 0xFF),
    },
    "icon_locked_dim": {  # dim orange
        "A": (0x4A, 0x2B, 0x00, 0xFF),
        "B": (0x80, 0x4A, 0x00, 0xFF),
        "S": (0x4A, 0x2B, 0x00, 0xFF),
    },
    "icon_unlocked": {  # gray
        "A": (0x5F, 0x5F, 0x5F, 0xFF),
        "B": (0x9A, 0x9A, 0x9A, 0xFF),
        "S": (0x5F, 0x5F, 0x5F, 0xFF),
    },
}


def render(size, palette):
    scale = size // len(MIC)
    rows = []
    for y in range(size):
        src_y = y // scale
        row = []
        for x in range(size):
            ch = MIC[src_y][x // scale]
            r, g, b, a = palette.get(ch, (0, 0, 0, 0))
            row.append(struct.pack("<BBBB", b, g, r, a))  # BGRA
        rows.append(b"".join(row))
    return b"".join(rows)


def bmp_entry(pixels, w, h):
    header = struct.pack(
        "<IiiHHIIiiII",
        40,        # biSize
        w,         # biWidth
        h * 2,     # biHeight (XOR + AND)
        1,         # biPlanes
        32,        # biBitCount
        0,         # biCompression = BI_RGB
        0,         # biSizeImage (can be 0 for BI_RGB)
        0, 0,      # pixels per meter
        0, 0,      # colors used / important
    )
    xor = b"".join(reversed([pixels[i * w * 4 : (i + 1) * w * 4] for i in range(h)]))
    mask_stride = ((w + 31) // 32) * 4
    mask = b"\x00" * (mask_stride * h)  # fully opaque via alpha; mask all zero
    return header + xor + mask


def write_ico(path, palette):
    images = [(16, render(16, palette)), (32, render(32, palette))]
    entries = [bmp_entry(px, s, s) for s, px in images]
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    dir_data = b""
    for (size, _), data in zip(images, entries):
        dir_data += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    with open(path, "wb") as f:
        f.write(header + dir_data + b"".join(entries))
    print(f"wrote {path} ({os.path.getsize(path)} bytes)")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, palette in PALETTES.items():
        write_ico(os.path.join(OUT_DIR, f"{name}.ico"), palette)


if __name__ == "__main__":
    main()
