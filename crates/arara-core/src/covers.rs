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
