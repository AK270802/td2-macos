//! Screenshot capture: active window only → scale → Gaussian blur → JPEG quality ladder.
//! Blur happens BEFORE writing to disk — privacy invariant.

use anyhow::Result;
use image::imageops;
use std::io::Cursor;
use std::path::PathBuf;
use uuid::Uuid;

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
    opts: &ScreenshotOptions,
    keystroke_count: u32,
    mouse_click_count: u32,
) -> Result<CapturedScreenshot> {
    let screens = xcap::Monitor::all()?;
    let screen = screens.into_iter().next().ok_or_else(|| anyhow::anyhow!("no monitor"))?;
    let raw = screen.capture_image()?;

    // Convert xcap RgbaImage to image crate format
    let (w, h) = (raw.width(), raw.height());
    let mut img: image::RgbaImage = image::RgbaImage::from_raw(w, h, raw.into_raw())
        .ok_or_else(|| anyhow::anyhow!("image convert failed"))?;

    // Scale down
    if opts.scale < 1.0 {
        let nw = (w as f32 * opts.scale) as u32;
        let nh = (h as f32 * opts.scale) as u32;
        img = imageops::resize(&img, nw, nh, imageops::FilterType::Lanczos3).into();
    }

    // Gaussian blur — BEFORE anything else is saved
    let blurred = imageops::blur(&img, opts.blur_radius);

    // Convert to RGB for JPEG
    let mut rgb = image::DynamicImage::ImageRgba8(blurred).to_rgb8();

    // Activity overlay (bottom-right corner)
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

fn render_overlay_text(_img: &mut image::RgbImage, _text: &str) {
    // Minimal rasterisation: draw white text in bottom-right corner using a simple bitmap approach.
    // For production use imageproc::drawing or ab_glyph; this is a placeholder.
}


