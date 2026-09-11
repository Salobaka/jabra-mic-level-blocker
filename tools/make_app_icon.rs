//! Generate the Windows app/window icon asset (pure std, no crates).
//!
//! Outputs windows/assets/icon_app.bin (orange, "locked") and
//! windows/assets/icon_app_gray.bin (gray, "unlocked"): tiny containers of
//! RT_ICON-format images (BITMAPINFOHEADER + bottom-up 32bpp BGRA + AND mask)
//! at several sizes, rendered from the same 16x16 pixel-art microphone as the
//! tray icons. Nearest-neighbor upscale keeps the blocky pixel style crisp.
//!
//! Run from the repo root:
//!   rustc -O tools/make_app_icon.rs -o make_app_icon.exe
//!   .\make_app_icon.exe

use std::fs;
use std::path::Path;

const SIZES: [u32; 9] = [16, 20, 24, 32, 40, 48, 64, 128, 256];

// 16x16 pixel-art microphone. '.' transparent, A outline, B body fill, S stand.
const MIC: [&str; 16] = [
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
];

// bright orange (matches icon_locked tray palette) and gray (icon_unlocked)
const PALETTES: [(&str, [u8; 3], [u8; 3]); 2] = [
    ("icon_app", [0xB2, 0x5E, 0x00], [0xFF, 0x95, 0x00]),
    ("icon_app_gray", [0x5F, 0x5F, 0x5F], [0x9A, 0x9A, 0x9A]),
];

fn push_u16(out: &mut Vec<u8>, v: u16) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn push_u32(out: &mut Vec<u8>, v: u32) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn push_i32(out: &mut Vec<u8>, v: i32) {
    out.extend_from_slice(&v.to_le_bytes());
}

/// One RT_ICON-format image: BITMAPINFOHEADER + bottom-up XOR + AND mask.
fn icon_image(size: u32, outline: [u8; 3], fill: [u8; 3]) -> Vec<u8> {
    let s = size as usize;
    let n = MIC.len();
    let mut top_down = vec![0u8; s * s * 4];
    for y in 0..s {
        let row = MIC[y * n / s].as_bytes();
        for x in 0..s {
            let (rgb, alpha) = match row[x * n / s] {
                b'A' | b'S' => (outline, 0xFF),
                b'B' => (fill, 0xFF),
                _ => ([0u8; 3], 0),
            };
            let i = (y * s + x) * 4;
            top_down[i] = rgb[2]; // B
            top_down[i + 1] = rgb[1]; // G
            top_down[i + 2] = rgb[0]; // R
            top_down[i + 3] = alpha;
        }
    }

    let mut out = Vec::with_capacity(40 + s * s * 4);
    push_u32(&mut out, 40); // biSize
    push_i32(&mut out, size as i32); // biWidth
    push_i32(&mut out, (size * 2) as i32); // biHeight: XOR + AND
    push_u16(&mut out, 1); // biPlanes
    push_u16(&mut out, 32); // biBitCount
    push_u32(&mut out, 0); // biCompression = BI_RGB
    push_u32(&mut out, 0); // biSizeImage
    push_i32(&mut out, 0); // biXPelsPerMeter
    push_i32(&mut out, 0); // biYPelsPerMeter
    push_u32(&mut out, 0); // biClrUsed
    push_u32(&mut out, 0); // biClrImportant
    for y in (0..s).rev() {
        out.extend_from_slice(&top_down[y * s * 4..(y + 1) * s * 4]);
    }
    // AND mask (1bpp), all zero: the 32bpp alpha channel drives transparency
    let stride = ((s + 31) / 32) * 4;
    out.resize(out.len() + stride * s, 0);
    out
}

fn main() {
    for (name, outline, fill) in PALETTES {
        let out_path = Path::new("windows").join("assets").join(format!("{name}.bin"));
        let mut out = Vec::new();
        push_u32(&mut out, SIZES.len() as u32);
        for size in SIZES {
            let img = icon_image(size, outline, fill);
            push_u32(&mut out, size);
            push_u32(&mut out, img.len() as u32);
            out.extend_from_slice(&img);
        }
        if let Some(dir) = out_path.parent() {
            fs::create_dir_all(dir).expect("create assets dir");
        }
        fs::write(&out_path, &out).expect("write icon container");
        println!("wrote {} ({} bytes)", out_path.display(), out.len());
    }
}
