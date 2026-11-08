//! Animated album covers ("motion artwork", the short looping videos Apple
//! Music shows on some albums).
//!
//! There is no official public API for these. A lookup service (by default
//! the public instance of github.com/m8tec/apple-music-animated-artworks at
//! artwork.m8tec.top, overridable with `ARARA_MOTION_URL`) answers with the
//! HLS playlist on Apple's CDN. We pick one H.264 variant of a modest size,
//! join its init segment and media segments into a single fragmented MP4
//! (no ffmpeg needed) and keep it in the cache folder, so every album is
//! fetched once. Only the artist and album names are sent to the service.
//!
//! The result is remembered in `kv` as `motion:<key>` → `{at, file}`
//! (`file` null = this album has no animated cover; retried after a month).

use serde_json::{json, Value};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::Duration;

use crate::db::Db;

const UA: &str = "AraraMusic/0.8 ( https://github.com/Githyot )";
/// Largest side of the variant we download. 486 px covers the album page
/// (260–300 px) and the panel at 2x, at about 1–2 MB per album.
pub const DEFAULT_SIDE: u32 = 486;
/// Never keep more than this from one album (the files are usually 1–3 MB).
const MAX_BYTES: u64 = 24 << 20;
/// "No animated cover" is asked again after 30 days, a failed attempt after 6 hours.
const NONE_SECS: i64 = 30 * 86400;
const FAIL_SECS: i64 = 6 * 3600;

fn base() -> String {
    std::env::var("ARARA_MOTION_URL")
        .unwrap_or_else(|_| "https://artwork.m8tec.top".to_owned())
        .trim_end_matches('/')
        .to_owned()
}

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new().timeout(Duration::from_secs(25)).user_agent(UA).build()
}

fn enc(s: &str) -> String {
    let mut o = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => o.push(b as char),
            _ => o.push_str(&format!("%{b:02X}")),
        }
    }
    o
}

fn norm(s: &str) -> String {
    s.to_lowercase().split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Cache key for an album: same artist + title → same file.
pub fn key(artist: &str, album: &str) -> String {
    blake3::hash(format!("{}\u{1f}{}", norm(artist), norm(album)).as_bytes()).to_hex()[..24].to_string()
}

pub enum Lookup {
    /// HLS master playlist of the square artwork.
    Found(String),
    /// The service answered: this album has no animated cover.
    None,
    /// Network/service error; try again later.
    Failed,
}

/// Ask the lookup service for the album's animated cover.
pub fn lookup(artist: &str, album: &str) -> Lookup {
    let url = format!("{}/api/v1/artwork/search?artist={}&album={}", base(), enc(artist), enc(album));
    match agent().get(&url).call() {
        Ok(r) => {
            let Ok(v) = r.into_json::<Value>() else { return Lookup::Failed };
            match v["url"].as_str().filter(|u| u.starts_with("http")) {
                Some(u) => Lookup::Found(u.to_owned()),
                None => Lookup::None,
            }
        }
        Err(ureq::Error::Status(404, _)) | Err(ureq::Error::Status(400, _)) => Lookup::None,
        Err(e) => {
            log::info!("motion cover lookup failed: {e}");
            Lookup::Failed
        }
    }
}

/// Resolve a playlist entry against the playlist's own URL.
pub fn join(base: &str, rel: &str) -> String {
    if rel.starts_with("http://") || rel.starts_with("https://") {
        return rel.to_owned();
    }
    if let Some(rest) = rel.strip_prefix('/') {
        // scheme://host + absolute path
        let host_end = base.find("://").map(|i| i + 3).and_then(|i| base[i..].find('/').map(|j| i + j)).unwrap_or(base.len());
        return format!("{}/{rest}", &base[..host_end]);
    }
    let dir = base.split('?').next().unwrap_or(base);
    let dir = &dir[..dir.rfind('/').map(|i| i + 1).unwrap_or(0)];
    format!("{dir}{rel}")
}

fn attr<'a>(line: &'a str, name: &str) -> Option<&'a str> {
    let pat = format!("{name}=");
    let mut i = 0;
    while let Some(p) = line[i..].find(&pat) {
        let at = i + p;
        // must start an attribute (after ':' or ',')
        if at == 0 || matches!(line.as_bytes()[at - 1], b':' | b',') {
            let v = &line[at + pat.len()..];
            return Some(if let Some(q) = v.strip_prefix('"') {
                &q[..q.find('"').unwrap_or(q.len())]
            } else {
                &v[..v.find(',').unwrap_or(v.len())]
            });
        }
        i = at + pat.len();
    }
    None
}

/// From a master playlist pick the H.264 variant whose side is the largest
/// one not above `max_side` (the smallest H.264 one if all are bigger), and
/// among equal sizes the lowest bitrate. H.264 plays everywhere; HEVC doesn't.
pub fn pick_variant(master: &str, master_url: &str, max_side: u32) -> Option<String> {
    let mut best: Option<(u32, u64, String)> = None; // (side, bandwidth, url)
    let mut smallest: Option<(u32, u64, String)> = None;
    let mut lines = master.lines();
    while let Some(l) = lines.next() {
        let l = l.trim();
        if !l.starts_with("#EXT-X-STREAM-INF:") {
            continue;
        }
        let Some(uri) = lines.by_ref().map(str::trim).find(|x| !x.is_empty() && !x.starts_with('#')) else { break };
        let codecs = attr(l, "CODECS").unwrap_or("avc1");
        if !codecs.split(',').all(|c| c.trim().starts_with("avc1") || c.trim().starts_with("mp4a")) {
            continue;
        }
        let side = attr(l, "RESOLUTION")
            .and_then(|r| r.split_once('x'))
            .and_then(|(w, h)| Some(w.parse::<u32>().ok()?.max(h.parse::<u32>().ok()?)))
            .unwrap_or(0);
        let bw = attr(l, "BANDWIDTH").and_then(|b| b.parse::<u64>().ok()).unwrap_or(u64::MAX);
        let cand = (side, bw, join(master_url, uri));
        if side <= max_side {
            let better = match &best {
                None => true,
                Some((s, b, _)) => side > *s || (side == *s && bw < *b),
            };
            if better {
                best = Some(cand.clone());
            }
        }
        let smaller = match &smallest {
            None => true,
            Some((s, b, _)) => side < *s || (side == *s && bw < *b),
        };
        if smaller {
            smallest = Some(cand);
        }
    }
    best.or(smallest).map(|c| c.2)
}

/// One piece of the output file: a URL and an optional byte range (start, length).
#[derive(Debug, Clone, PartialEq)]
pub struct Part {
    pub url: String,
    pub range: Option<(u64, u64)>,
}

fn byterange(v: &str, next_start: u64) -> Option<(u64, u64)> {
    let (len, start) = match v.split_once('@') {
        Some((l, s)) => (l.trim().parse().ok()?, s.trim().parse().ok()?),
        None => (v.trim().parse().ok()?, next_start),
    };
    Some((start, len))
}

/// The init segment followed by every media segment of a media playlist,
/// with neighbouring byte ranges of the same file merged into one request.
/// Returns None for encrypted streams.
pub fn media_parts(media: &str, media_url: &str) -> Option<Vec<Part>> {
    let mut parts: Vec<Part> = vec![];
    let mut pending: Option<(u64, u64)> = None;
    let mut last_end: std::collections::HashMap<String, u64> = Default::default();
    for l in media.lines().map(str::trim) {
        if let Some(rest) = l.strip_prefix("#EXT-X-KEY:") {
            if attr(rest, "METHOD").is_some_and(|m| m != "NONE") {
                return None;
            }
        } else if let Some(rest) = l.strip_prefix("#EXT-X-MAP:") {
            let url = join(media_url, attr(rest, "URI")?);
            let range = attr(rest, "BYTERANGE").and_then(|b| byterange(b, 0));
            if let Some((s, n)) = range {
                last_end.insert(url.clone(), s + n);
            }
            parts.push(Part { url, range });
        } else if let Some(rest) = l.strip_prefix("#EXT-X-BYTERANGE:") {
            // No "@start": continues where the previous range of that file ended.
            pending = byterange(rest, u64::MAX);
        } else if !l.is_empty() && !l.starts_with('#') {
            let url = join(media_url, l);
            let range = pending.take().map(|(s, n)| {
                let s = if s == u64::MAX { *last_end.get(&url).unwrap_or(&0) } else { s };
                (s, n)
            });
            if let Some((s, n)) = range {
                last_end.insert(url.clone(), s + n);
            }
            if let (Some(prev), Some((s, n))) = (parts.last_mut(), range) {
                if prev.url == url {
                    if let Some((ps, pn)) = prev.range {
                        if ps + pn == s {
                            prev.range = Some((ps, pn + n));
                            continue;
                        }
                    }
                }
            }
            parts.push(Part { url, range });
        }
    }
    (!parts.is_empty()).then_some(parts)
}

fn get_text(a: &ureq::Agent, url: &str) -> Option<String> {
    let r = a.get(url).call().ok()?;
    let mut s = String::new();
    r.into_reader().take(2 << 20).read_to_string(&mut s).ok()?;
    Some(s)
}

/// Download the animated cover behind `master_url` into `dest` (an .mp4).
pub fn download(master_url: &str, max_side: u32, dest: &Path) -> Option<()> {
    let a = agent();
    let master = get_text(&a, master_url)?;
    // A media playlist given directly (no variants) works too.
    let media_url = if master.contains("#EXT-X-STREAM-INF") { pick_variant(&master, master_url, max_side)? } else { master_url.to_owned() };
    let media = if media_url == master_url { master } else { get_text(&a, &media_url)? };
    let parts = media_parts(&media, &media_url)?;
    let tmp = dest.with_extension(format!("{}.part", std::process::id()));
    let res = (|| -> Option<()> {
        let mut out = std::fs::File::create(&tmp).ok()?;
        let mut total = 0u64;
        for p in &parts {
            let mut req = a.get(&p.url);
            if let Some((s, n)) = p.range {
                req = req.set("Range", &format!("bytes={s}-{}", s + n - 1));
            }
            let r = req.call().ok()?;
            let full_body = p.range.is_some() && r.status() == 200;
            let mut rd = r.into_reader().take(MAX_BYTES + 1 - total);
            if full_body {
                // Server ignored the range: skip to it ourselves.
                let (s, n) = p.range.unwrap();
                std::io::copy(&mut rd.by_ref().take(s), &mut std::io::sink()).ok()?;
                total += std::io::copy(&mut rd.take(n), &mut out).ok()?;
            } else {
                total += std::io::copy(&mut rd, &mut out).ok()?;
            }
            if total > MAX_BYTES {
                return None;
            }
        }
        (total > 1024).then_some(())
    })();
    if res.is_none() {
        let _ = std::fs::remove_file(&tmp);
        return None;
    }
    std::fs::rename(&tmp, dest).ok()
}

/// What we know about an album without going online.
pub enum Cached {
    Ready(PathBuf),
    /// Asked recently: no animated cover (or it failed a moment ago).
    Missing,
    Unknown,
}

pub fn cached(db: &Db, dir: &Path, artist: &str, album: &str, now: i64) -> Cached {
    let k = key(artist, album);
    let Some(v) = db.get_kv(&format!("motion:{k}")).ok().flatten().and_then(|s| serde_json::from_str::<Value>(&s).ok()) else {
        return Cached::Unknown;
    };
    if let Some(f) = v["file"].as_str() {
        let p = dir.join(f);
        return if p.exists() { Cached::Ready(p) } else { Cached::Unknown };
    }
    let at = v["at"].as_i64().unwrap_or(0);
    let wait = if v["fail"].as_bool().unwrap_or(false) { FAIL_SECS } else { NONE_SECS };
    if now - at < wait { Cached::Missing } else { Cached::Unknown }
}

/// Look up and download one album's animated cover (blocking). Returns the file.
pub fn fetch(db: &Db, dir: &Path, artist: &str, album: &str, now: i64, max_side: u32) -> Option<PathBuf> {
    let k = key(artist, album);
    let kv = format!("motion:{k}");
    let (file, fail) = match lookup(artist, album) {
        Lookup::Found(master) => {
            let _ = std::fs::create_dir_all(dir);
            let name = format!("{k}.mp4");
            match download(&master, max_side, &dir.join(&name)) {
                Some(()) => (Some(name), false),
                None => (None, true),
            }
        }
        Lookup::None => (None, false),
        Lookup::Failed => (None, true),
    };
    let _ = db.set_kv(&kv, &json!({ "at": now, "file": file, "fail": fail }).to_string());
    file.map(|f| dir.join(f))
}

/// Forget every downloaded animated cover (files and remembered answers).
pub fn clear(db: &Db, dir: &Path) -> usize {
    let _ = db.conn.execute("DELETE FROM kv WHERE k LIKE 'motion:%'", []);
    let mut n = 0;
    if let Ok(rd) = std::fs::read_dir(dir) {
        for e in rd.flatten() {
            if e.path().extension().is_some_and(|x| x == "mp4") && std::fs::remove_file(e.path()).is_ok() {
                n += 1;
            }
        }
    }
    n
}

/// Total size of the downloaded animated covers, in bytes.
pub fn disk_usage(dir: &Path) -> u64 {
    std::fs::read_dir(dir)
        .map(|rd| rd.flatten().filter_map(|e| e.metadata().ok()).filter(|m| m.is_file()).map(|m| m.len()).sum())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    const MASTER: &str = "#EXTM3U\n#EXT-X-VERSION:7\n\
#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=1,CODECS=\"avc1.64001f\",RESOLUTION=486x486,URI=\"x_iframes.m3u8\"\n\
#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=2134545,BANDWIDTH=2849431,CODECS=\"avc1.64001f\",RESOLUTION=768x768\n\
https://cdn.example/a/v_768.m3u8\n\
#EXT-X-STREAM-INF:BANDWIDTH=2432741,CODECS=\"hvc1.2.20000000.L123.B0\",RESOLUTION=486x486\n\
v_hevc_486.m3u8\n\
#EXT-X-STREAM-INF:BANDWIDTH=371068,CODECS=\"avc1.64001f\",RESOLUTION=360x360\n\
v_360.m3u8\n\
#EXT-X-STREAM-INF:BANDWIDTH=1471210,CODECS=\"avc1.64001f\",RESOLUTION=486x486\n\
v_486_hi.m3u8\n\
#EXT-X-STREAM-INF:BANDWIDTH=1022967,CODECS=\"avc1.64001f\",RESOLUTION=486x486\n\
v_486.m3u8\n";

    #[test]
    fn picks_h264_variant_by_size() {
        let u = "https://cdn.example/a/P1_default.m3u8";
        assert_eq!(pick_variant(MASTER, u, 486).unwrap(), "https://cdn.example/a/v_486.m3u8");
        assert_eq!(pick_variant(MASTER, u, 400).unwrap(), "https://cdn.example/a/v_360.m3u8");
        assert_eq!(pick_variant(MASTER, u, 2000).unwrap(), "https://cdn.example/a/v_768.m3u8");
        assert_eq!(pick_variant(MASTER, u, 100).unwrap(), "https://cdn.example/a/v_360.m3u8");
    }

    #[test]
    fn merges_byte_ranges_of_one_file() {
        let media = "#EXTM3U\n#EXT-X-MAP:URI=\"v-.mp4\",BYTERANGE=\"898@0\"\n\
#EXTINF:3.5,\n#EXT-X-BYTERANGE:258033@898\nv-.mp4\n\
#EXTINF:3.5,\n#EXT-X-BYTERANGE:404099@258931\nv-.mp4\n\
#EXTINF:3.5,\n#EXT-X-BYTERANGE:100\nv-.mp4\n#EXT-X-ENDLIST\n";
        let p = media_parts(media, "https://cdn.example/a/v.m3u8").unwrap();
        assert_eq!(p, vec![Part { url: "https://cdn.example/a/v-.mp4".into(), range: Some((0, 898 + 258033 + 404099 + 100)) }]);
    }

    #[test]
    fn separate_segments_and_encryption() {
        let media = "#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:2,\nseg1.m4s\n#EXTINF:2,\nseg2.m4s\n";
        let p = media_parts(media, "https://h/x/v.m3u8").unwrap();
        assert_eq!(p.iter().map(|p| p.url.as_str()).collect::<Vec<_>>(), ["https://h/x/init.mp4", "https://h/x/seg1.m4s", "https://h/x/seg2.m4s"]);
        assert!(media_parts("#EXT-X-KEY:METHOD=AES-128,URI=\"k\"\nseg.ts\n", "https://h/v.m3u8").is_none());
    }

    #[test]
    fn joins_urls() {
        assert_eq!(join("https://h/a/b.m3u8?x=1", "c.mp4"), "https://h/a/c.mp4");
        assert_eq!(join("https://h/a/b.m3u8", "/z/c.mp4"), "https://h/z/c.mp4");
        assert_eq!(join("https://h/a/b.m3u8", "https://o/c.mp4"), "https://o/c.mp4");
    }
}

#[cfg(test)]
mod live {
    /// `ARARA_MOTION_LIVE=1 cargo test -p arara-core motion::live -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn downloads_a_real_cover() {
        let super::Lookup::Found(m) = super::lookup("Gorillaz", "Plastic Beach") else { panic!("no lookup") };
        let out = std::env::temp_dir().join("arara-motion-live.mp4");
        super::download(&m, super::DEFAULT_SIDE, &out).expect("download");
        let n = std::fs::metadata(&out).unwrap().len();
        println!("{} bytes -> {}", n, out.display());
        assert!(n > 100_000);
    }
}
