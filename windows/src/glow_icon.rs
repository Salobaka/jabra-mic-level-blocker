//! Smooth glowing orange dot: tray animation frames (pure std, no crates).
//!
//! Replaces the old two-icon hard blink (locked/locked_dim flip every 400 ms)
//! with a sinusoidal glow pulse around the same 16x16 pixel-art microphone
//! used by tools/make_app_icon.rs. The mic is drawn at 2x over a soft radial
//! halo whose alpha follows a cosine over one cycle, so the pulse eases in and
//! out instead of snapping on/off.
//!
//! Each frame is a complete single-image ICO byte blob (ICONDIR + one 32bpp
//! BGRA RT_ICON image), decoded by nwg via WIC — the same layout as
//! windows/assets/icon_locked.ico.

/// Frame edge size in pixels (2x the 16x16 art, for a smoother halo).
pub const SIZE: usize = 32;
/// Frames in one full glow cycle. At an 80 ms timer tick this is a ~1.6 s pulse.
pub const FRAMES: usize = 20;

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

// bright orange, matching tools/make_app_icon.rs palettes
const OUTLINE: [u8; 3] = [0xB2, 0x5E, 0x00];
const FILL: [u8; 3] = [0xFF, 0x95, 0x00];
/// Halo color: saturated orange so the glow reads clearly at tray size.
const GLOW: [u8; 3] = [0xFF, 0xA0, 0x30];

/// Halo center in 32x32 space (mic body is centered at x=8, slightly above
/// middle at y=7 in 16x16 space).
const CENTER: (f64, f64) = (16.0, 14.0);
/// Halo radius: reaches the frame edges with a soft falloff.
const RADIUS: f64 = 15.0;
/// Peak halo alpha at full intensity.
const MAX_ALPHA: f64 = 0.95;

/// Glow intensity (0.0..=1.0) for a frame index: cosine ease over the cycle.
pub fn intensity(phase: usize) -> f64 {
    let t = (phase % FRAMES) as f64 / FRAMES as f64;
    0.5 - 0.5 * (std::f64::consts::TAU * t).cos()
}

/// Top-down BGRA pixels (SIZE x SIZE) with halo and mic composited.
pub fn render_pixels(phase: usize) -> Vec<u8> {
    let intensity = intensity(phase);
    let mut px = vec![0u8; SIZE * SIZE * 4];

    // Radial glow halo behind the mic.
    if intensity > 0.0 {
        for y in 0..SIZE {
            for x in 0..SIZE {
                let dx = x as f64 + 0.5 - CENTER.0;
                let dy = y as f64 + 0.5 - CENTER.1;
                let g = 1.0 - (dx * dx + dy * dy).sqrt() / RADIUS;
                if g <= 0.0 {
                    continue;
                }
                let a = g * g * intensity * MAX_ALPHA;
                let i = (y * SIZE + x) * 4;
                px[i] = GLOW[2]; // B
                px[i + 1] = GLOW[1]; // G
                px[i + 2] = GLOW[0]; // R
                px[i + 3] = (a * 255.0).round() as u8;
            }
        }
    }

    // Mic on top, nearest-neighbor 2x upscale (mirrors make_app_icon.rs).
    let scale = SIZE / 16;
    for y in 0..SIZE {
        let row = MIC[y / scale].as_bytes();
        for x in 0..SIZE {
            let (rgb, alpha) = match row[x / scale] {
                b'A' | b'S' => (OUTLINE, 0xFF),
                b'B' => (FILL, 0xFF),
                _ => continue,
            };
            let i = (y * SIZE + x) * 4;
            px[i] = rgb[2]; // B
            px[i + 1] = rgb[1]; // G
            px[i + 2] = rgb[0]; // R
            px[i + 3] = alpha;
        }
    }

    px
}

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
fn icon_image(top_down_bgra: &[u8]) -> Vec<u8> {
    let s = SIZE;
    let mut out = Vec::with_capacity(40 + s * s * 4);
    push_u32(&mut out, 40); // biSize
    push_i32(&mut out, s as i32); // biWidth
    push_i32(&mut out, (s * 2) as i32); // biHeight: XOR + AND
    push_u16(&mut out, 1); // biPlanes
    push_u16(&mut out, 32); // biBitCount
    push_u32(&mut out, 0); // biCompression = BI_RGB
    push_u32(&mut out, 0); // biSizeImage
    push_i32(&mut out, 0); // biXPelsPerMeter
    push_i32(&mut out, 0); // biYPelsPerMeter
    push_u32(&mut out, 0); // biClrUsed
    push_u32(&mut out, 0); // biClrImportant
    for y in (0..s).rev() {
        out.extend_from_slice(&top_down_bgra[y * s * 4..(y + 1) * s * 4]);
    }
    // AND mask (1bpp), all zero: the 32bpp alpha channel drives transparency
    let stride = s.div_ceil(32) * 4;
    out.resize(out.len() + stride * s, 0);
    out
}

/// Full single-image ICO byte blob for a frame index, ready for
/// `nwg::Icon::from_bin`.
pub fn frame_ico(phase: usize) -> Vec<u8> {
    let image = icon_image(&render_pixels(phase));
    let mut out = Vec::with_capacity(22 + image.len());
    push_u16(&mut out, 0); // reserved
    push_u16(&mut out, 1); // type = icon
    push_u16(&mut out, 1); // image count
    out.push(SIZE as u8); // width
    out.push(SIZE as u8); // height
    out.push(0); // color count
    out.push(0); // reserved
    push_u16(&mut out, 1); // planes
    push_u16(&mut out, 32); // bit count
    push_u32(&mut out, image.len() as u32); // image length
    push_u32(&mut out, 22); // image offset
    out.extend_from_slice(&image);
    out
}
