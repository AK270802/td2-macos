//! Screenshot capture: active window crop → scale → Gaussian blur → activity
//! overlay → JPEG quality ladder.
//!
//! Privacy invariants: the image is cropped to the ACTIVE WINDOW (not the full
//! desktop) whenever the platform reports a window rect, and blur is applied
//! BEFORE anything is written to disk. The unblurred image never exists
//! outside process memory.

use anyhow::Result;
use image::imageops;
use std::io::Cursor;
use std::path::PathBuf;
use uuid::Uuid;
use crate::platform::WindowRect;

pub struct ScreenshotOptions {
    pub blur_radius: f32,
    pub scale: f32,
    pub jpeg_quality: u8,
    pub max_kb: u32,
}

impl Default for ScreenshotOptions {
    fn default() -> Self {
        Self { blur_radius: 8.0, scale: 0.5, jpeg_quality: 60, max_kb: 150 }
    }
}

pub struct CapturedScreenshot {
    pub path: PathBuf,
    pub uuid: Uuid,
    pub ts: i64,
    pub app_name: Option<String>,
    pub window_title: Option<String>,
}

pub fn capture_and_save(
    out_dir: &std::path::Path,
    app_name: Option<String>,
    window_title: Option<String>,
    window_rect: Option<WindowRect>,
    opts: &ScreenshotOptions,
    keystroke_count: u32,
    mouse_click_count: u32,
) -> Result<CapturedScreenshot> {
    // Pick the monitor containing the active window (multi-monitor correct),
    // falling back to the first monitor.
    let screens = xcap::Monitor::all()?;
    let screen = match (&window_rect, screens.len()) {
        (Some(r), n) if n > 1 => {
            let cx = r.x + (r.width as i32) / 2;
            let cy = r.y + (r.height as i32) / 2;
            screens.into_iter().find(|m| {
                // xcap 0.9's Monitor accessors return `Result` (a monitor can
                // fail to report its geometry, e.g. mid-disconnect) — treat
                // that as "doesn't contain the point" rather than propagating,
                // since this is just picking which of several monitors to use.
                let (Ok(mx), Ok(my), Ok(mw), Ok(mh)) = (m.x(), m.y(), m.width(), m.height()) else {
                    return false;
                };
                cx >= mx && cx < mx + mw as i32 &&
                cy >= my && cy < my + mh as i32
            })
        }
        (_, _) => None,
    }
    .map(Ok)
    .unwrap_or_else(|| {
        xcap::Monitor::all()?
            .into_iter()
            .next()
            .ok_or_else(|| anyhow::anyhow!("no monitor"))
    })?;

    let mon_x = screen.x()?;
    let mon_y = screen.y()?;
    let raw = screen.capture_image()?;

    let (w, h) = (raw.width(), raw.height());
    let mut img: image::RgbaImage = image::RgbaImage::from_raw(w, h, raw.into_raw())
        .ok_or_else(|| anyhow::anyhow!("image convert failed"))?;

    // Crop to the active window (privacy: never ship other windows' content).
    if let Some(r) = window_rect {
        let x = (r.x - mon_x).max(0) as u32;
        let y = (r.y - mon_y).max(0) as u32;
        if x < w && y < h && r.width > 0 && r.height > 0 {
            let cw = r.width.min(w - x);
            let ch = r.height.min(h - y);
            if cw >= 40 && ch >= 40 {
                img = imageops::crop_imm(&img, x, y, cw, ch).to_image();
            }
        }
    }

    // Scale down
    let (w, h) = (img.width(), img.height());
    if opts.scale < 1.0 {
        let nw = ((w as f32 * opts.scale) as u32).max(1);
        let nh = ((h as f32 * opts.scale) as u32).max(1);
        img = imageops::resize(&img, nw, nh, imageops::FilterType::Lanczos3);
    }

    // Gaussian blur — BEFORE anything else is saved
    let blurred = imageops::blur(&img, opts.blur_radius.max(0.1));

    // Convert to RGB for JPEG
    let mut rgb = image::DynamicImage::ImageRgba8(blurred).to_rgb8();

    // Activity overlay (bottom-right corner) — counts only
    if keystroke_count > 0 || mouse_click_count > 0 {
        let label = format!("KB: {}  Mouse: {}", keystroke_count, mouse_click_count);
        render_overlay_text(&mut rgb, &label);
    }

    // JPEG quality ladder: 60 → 40 → 25
    let max_bytes = opts.max_kb as usize * 1024;
    let jpeg_data = encode_jpeg(&rgb, opts.jpeg_quality, max_bytes)?;

    std::fs::create_dir_all(out_dir)?;
    let id = Uuid::new_v4();
    let ts = chrono::Utc::now().timestamp();
    let path = out_dir.join(format!("{id}.jpg"));
    std::fs::write(&path, &jpeg_data)?;

    Ok(CapturedScreenshot { path, uuid: id, ts, app_name, window_title })
}

fn encode_jpeg(img: &image::RgbImage, quality: u8, max_bytes: usize) -> Result<Vec<u8>> {
    for q in [quality, 40, 25] {
        let mut buf = Cursor::new(Vec::new());
        let enc = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut buf, q);
        img.write_with_encoder(enc)?;
        let data = buf.into_inner();
        if data.len() <= max_bytes || q == 25 {
            return Ok(data);
        }
    }
    unreachable!()
}

// ── Bitmap-font overlay ──────────────────────────────────────────────────────
// Embedded 5×7 pixel font covering exactly the overlay alphabet
// ("KB: <n>  Mouse: <n>"). No external font files or licensing needed.

const GLYPH_W: u32 = 5;
const GLYPH_H: u32 = 7;

fn glyph(c: char) -> Option<[u8; 7]> {
    Some(match c {
        '0' => [0x0E,0x11,0x13,0x15,0x19,0x11,0x0E],
        '1' => [0x04,0x0C,0x04,0x04,0x04,0x04,0x0E],
        '2' => [0x0E,0x11,0x01,0x02,0x04,0x08,0x1F],
        '3' => [0x1F,0x02,0x04,0x02,0x01,0x11,0x0E],
        '4' => [0x02,0x06,0x0A,0x12,0x1F,0x02,0x02],
        '5' => [0x1F,0x10,0x1E,0x01,0x01,0x11,0x0E],
        '6' => [0x06,0x08,0x10,0x1E,0x11,0x11,0x0E],
        '7' => [0x1F,0x01,0x02,0x04,0x08,0x08,0x08],
        '8' => [0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E],
        '9' => [0x0E,0x11,0x11,0x0F,0x01,0x02,0x0C],
        'K' => [0x11,0x12,0x14,0x18,0x14,0x12,0x11],
        'B' => [0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E],
        'M' => [0x11,0x1B,0x15,0x15,0x11,0x11,0x11],
        'o' => [0x00,0x00,0x0E,0x11,0x11,0x11,0x0E],
        'u' => [0x00,0x00,0x11,0x11,0x11,0x13,0x0D],
        's' => [0x00,0x00,0x0F,0x10,0x0E,0x01,0x1E],
        'e' => [0x00,0x00,0x0E,0x11,0x1F,0x10,0x0E],
        ':' => [0x00,0x04,0x00,0x00,0x04,0x00,0x00],
        ' ' => [0x00; 7],
        _ => return None,
    })
}

/// Draw `text` in the bottom-right corner: white glyphs at 2× scale over a
/// dark backing box so counts stay legible on any blurred background.
fn render_overlay_text(img: &mut image::RgbImage, text: &str) {
    const SCALE: u32 = 2;
    const PAD: u32 = 6;
    let char_w = (GLYPH_W + 1) * SCALE;
    let text_w = char_w * text.chars().count() as u32;
    let text_h = GLYPH_H * SCALE;
    let (iw, ih) = (img.width(), img.height());
    if text_w + PAD * 2 + 4 > iw || text_h + PAD * 2 + 4 > ih {
        return;
    }
    let box_x = iw - text_w - PAD * 2 - 4;
    let box_y = ih - text_h - PAD * 2 - 4;
    let box_w = text_w + PAD * 2;
    let box_h = text_h + PAD * 2;

    for y in box_y..box_y + box_h {
        for x in box_x..box_x + box_w {
            let p = img.get_pixel_mut(x, y);
            p.0 = [(p.0[0] / 4), (p.0[1] / 4), (p.0[2] / 4)];
        }
    }

    let mut cx = box_x + PAD;
    let cy = box_y + PAD;
    for c in text.chars() {
        if let Some(rows) = glyph(c) {
            for (ry, row) in rows.iter().enumerate() {
                for rx in 0..GLYPH_W {
                    if (row >> (GLYPH_W - 1 - rx)) & 1 == 1 {
                        for sy in 0..SCALE {
                            for sx in 0..SCALE {
                                let px = cx + rx * SCALE + sx;
                                let py = cy + ry as u32 * SCALE + sy;
                                if px < iw && py < ih {
                                    img.put_pixel(px, py, image::Rgb([255, 255, 255]));
                                }
                            }
                        }
                    }
                }
            }
        }
        cx += char_w;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn overlay_alphabet_is_complete() {
        for c in "KB: 0123456789  Mouse:".chars() {
            assert!(glyph(c).is_some(), "missing glyph for {c:?}");
        }
    }

    #[test]
    fn overlay_draws_white_pixels() {
        let mut img = image::RgbImage::from_pixel(400, 200, image::Rgb([90, 90, 90]));
        render_overlay_text(&mut img, "KB: 42  Mouse: 7");
        let white = img.pixels().filter(|p| p.0 == [255, 255, 255]).count();
        assert!(white > 50, "expected overlay glyph pixels, got {white}");
    }

    #[test]
    fn overlay_skipped_on_tiny_images() {
        let mut img = image::RgbImage::from_pixel(20, 10, image::Rgb([90, 90, 90]));
        render_overlay_text(&mut img, "KB: 42  Mouse: 7"); // must not panic
    }
}
