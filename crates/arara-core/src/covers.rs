//! On-disk thumbnail cache, content-addressed by blake3.
//!
//! Each album cover is stored once as `<hash>-<size>.jpg`. Nothing is kept
//! decoded in RAM here; the UI's image provider decodes only what is on
//! screen and Qt's pixmap cache bounds that.

use image::imageops::FilterType;
use std::path::{Path, PathBuf};

use crate::Result;

/// Sizes generated at scan time. Grid tiles use 256, the "now playing" view 640.
pub const THUMB_SIZES: &[u32] = &[256, 640];

pub struct CoverCache {
    dir: PathBuf,
}

impl CoverCache {
    pub fn new(dir: impl Into<PathBuf>) -> Result<Self> {
        let dir = dir.into();
        std::fs::create_dir_all(&dir)?;
        Ok(Self { dir })
    }

    pub fn path_for(&self, hash: &str, size: u32) -> PathBuf {
        self.dir.join(format!("{hash}-{size}.jpg"))
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    /// Store an image, returning its hash. Already-cached images are skipped without decoding.
    pub fn store(&self, bytes: &[u8]) -> Result<String> {
        let hash = blake3::hash(bytes).to_hex()[..32].to_string();
        if THUMB_SIZES.iter().all(|s| self.path_for(&hash, *s).exists()) {
            return Ok(hash);
        }
        let img = image::load_from_memory(bytes)?;
        for &s in THUMB_SIZES {
            let out = self.path_for(&hash, s);
            if out.exists() {
                continue;
            }
            let thumb = if img.width() > s || img.height() > s {
                img.resize(s, s, FilterType::Triangle)
            } else {
                img.clone()
            };
            // Unique temp name: two albums can share the same art and be written concurrently.
            static N: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
            let n = N.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            let tmp = out.with_extension(format!("{}.{n}.tmp", std::process::id()));
            thumb.to_rgb8().save_with_format(&tmp, image::ImageFormat::Jpeg)
                .map_err(|e| { let _ = std::fs::remove_file(&tmp); e })?;
            std::fs::rename(tmp, out)?;
        }
        Ok(hash)
    }
}

/// A few representative colours of a thumbnail (top-left, top-right,
/// bottom-left, bottom-right of a 2×2 downscale), as "#rrggbb", for the
/// gradient behind the lyrics screen. Very dark/light colours are pulled
/// towards the middle so white text stays readable.
pub fn palette(path: &std::path::Path) -> Vec<String> {
    let Ok(img) = image::open(path) else { return vec![] };
    let small = img.resize_exact(2, 2, image::imageops::FilterType::Triangle).to_rgb8();
    small
        .pixels()
        .map(|p| {
            let [r, g, b] = p.0.map(|c| c as f32);
            let l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
            // keep the hue, clamp the luminance into a band that works under white text
            let target = l.clamp(55.0, 120.0);
            let k = if l > 1.0 { target / l } else { 1.0 };
            let f = |c: f32| ((c * k).clamp(0.0, 255.0)) as u8;
            let (r, g, b) = if l <= 1.0 { (40, 40, 48) } else { (f(r), f(g), f(b)) };
            format!("#{r:02x}{g:02x}{b:02x}")
        })
        .collect()
}

/// A small, heavily blurred copy of a thumbnail (written once next to it as
/// `<name>-blur.jpg`), for soft full-screen backgrounds: scaled up by the GPU
/// it looks like a big blur at the cost of a 48×48 image.
pub fn blurred(path: &std::path::Path) -> Option<std::path::PathBuf> {
    let out = path.with_file_name(format!("{}-blur.jpg", path.file_stem()?.to_string_lossy()));
    if out.exists() {
        return Some(out);
    }
    let img = image::open(path).ok()?;
    let small = img.resize_exact(48, 48, image::imageops::FilterType::Triangle);
    let soft = image::imageops::blur(&small.to_rgb8(), 4.0);
    soft.save(&out).ok()?;
    Some(out)
}
