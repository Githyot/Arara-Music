//! Synced lyrics with karaoke (word-level) timing.
//!
//! Resolution order, first hit wins and is cached in SQLite:
//! 1. cached row in `lyrics` table (including a negative "none" result, retried after 7 days)
//! 2. sidecar file next to the track: `song.lrc` / `song.txt`
//! 3. embedded tag (USLT / LYRICS / ©lyr)
//! 4. LRCLIB `/api/get` (exact match by title, artist, album, duration)
//! 5. LRCLIB `/api/search` (fuzzy fallback; picks the closest duration that has synced lyrics)
//!
//! The LRC parser understands *enhanced LRC* (`[00:12.00]<00:12.00>Hel<00:12.40>lo`)
//! so the UI can paint each word as it is sung. Plain line-synced LRC gets
//! word timings interpolated evenly across the line, so karaoke mode always works.

use serde::Deserialize;
use std::path::Path;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::db::Db;
use crate::Result;

const LRCLIB: &str = "https://lrclib.net/api";
const USER_AGENT: &str = concat!("AraraMusic/", env!("CARGO_PKG_VERSION"), " (https://github.com/Githyot)");
const NEGATIVE_TTL_SECS: i64 = 7 * 24 * 3600;

#[derive(Debug, Clone, PartialEq)]
pub struct Word {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Line {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
    pub words: Vec<Word>,
    /// true when word timings came from the file, false when interpolated.
    pub word_synced: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Lyrics {
    Synced(Vec<Line>),
    Plain(String),
    None,
}

impl Lyrics {
    /// Index of the line active at `pos_ms` (binary search; called every UI frame).
    pub fn line_at(lines: &[Line], pos_ms: u64) -> Option<usize> {
        match lines.binary_search_by(|l| l.start_ms.cmp(&pos_ms)) {
            Ok(i) => Some(i),
            Err(0) => None,
            Err(i) => Some(i - 1),
        }
    }
}

fn parse_ts(s: &str) -> Option<u64> {
    // mm:ss(.xx|.xxx) — also accepts mm:ss:xx used by some taggers
    let s = s.trim();
    let (m, rest) = s.split_once(':')?;
    let m: u64 = m.parse().ok()?;
    let (sec, frac) = match rest.split_once(['.', ':']) {
        Some((a, b)) => (a, b),
        None => (rest, "0"),
    };
    let sec: u64 = sec.parse().ok()?;
    let frac_ms = match frac.len() {
        0 => 0,
        1 => frac.parse::<u64>().ok()? * 100,
        2 => frac.parse::<u64>().ok()? * 10,
        _ => frac[..3].parse::<u64>().ok()?,
    };
    Some(m * 60_000 + sec * 1000 + frac_ms)
}

/// Parse (enhanced) LRC. Returns lines sorted by start time with end times filled in.
pub fn parse_lrc(src: &str, duration_ms: Option<u64>) -> Vec<Line> {
    let mut offset: i64 = 0;
    let mut lines: Vec<Line> = Vec::new();

    for raw in src.lines() {
        let mut rest = raw.trim();
        let mut stamps = Vec::new();
        while let Some(stripped) = rest.strip_prefix('[') {
            let Some(end) = stripped.find(']') else { break };
            let tag = &stripped[..end];
            if let Some(v) = tag.strip_prefix("offset:") {
                offset = v.trim().parse().unwrap_or(0);
            } else if let Some(t) = parse_ts(tag) {
                stamps.push(t);
            }
            rest = &stripped[end + 1..];
        }
        if stamps.is_empty() {
            continue;
        }

        // Word stamps: <mm:ss.xx>word
        let mut words = Vec::new();
        let mut plain = String::new();
        if rest.contains('<') {
            let mut cur_t: Option<u64> = None;
            let mut cur = String::new();
            let mut s = rest;
            while !s.is_empty() {
                if let Some(after) = s.strip_prefix('<') {
                    if let Some(end) = after.find('>') {
                        if let Some(t) = parse_ts(&after[..end]) {
                            if let Some(st) = cur_t {
                                if !cur.is_empty() {
                                    words.push(Word { start_ms: st, end_ms: t, text: cur.clone() });
                                }
                            }
                            plain.push_str(&cur);
                            cur.clear();
                            cur_t = Some(t);
                            s = &after[end + 1..];
                            continue;
                        }
                    }
                }
                let ch = s.chars().next().unwrap();
                cur.push(ch);
                s = &s[ch.len_utf8()..];
            }
            if let Some(st) = cur_t {
                if !cur.is_empty() {
                    words.push(Word { start_ms: st, end_ms: st, text: cur.clone() });
                }
            }
            plain.push_str(&cur);
        } else {
            plain.push_str(rest);
        }
        let word_synced = !words.is_empty();
        let text = plain.trim().to_string();

        for &t in &stamps {
            let t = (t as i64 - offset).max(0) as u64;
            let shift = |w: &Word| Word {
                start_ms: (w.start_ms as i64 - offset).max(0) as u64,
                end_ms: (w.end_ms as i64 - offset).max(0) as u64,
                text: w.text.clone(),
            };
            lines.push(Line {
                start_ms: t,
                end_ms: t,
                text: text.clone(),
                words: words.iter().map(shift).collect(),
                word_synced,
            });
        }
    }

    lines.sort_by_key(|l| l.start_ms);
    let n = lines.len();
    for i in 0..n {
        let next = if i + 1 < n {
            lines[i + 1].start_ms
        } else {
            duration_ms.unwrap_or(lines[i].start_ms + 5000).max(lines[i].start_ms)
        };
        let l = &mut lines[i];
        l.end_ms = next;
        if l.word_synced {
            if let Some(last) = l.words.last_mut() {
                if last.end_ms <= last.start_ms {
                    last.end_ms = next;
                }
            }
        } else if !l.text.is_empty() {
            l.words = interpolate_words(&l.text, l.start_ms, next);
        }
    }
    lines
}

/// Spread a line's duration across its words, weighted by character count.
fn interpolate_words(text: &str, start: u64, end: u64) -> Vec<Word> {
    let toks: Vec<&str> = text.split_inclusive(' ').collect();
    let total: usize = toks.iter().map(|t| t.trim().chars().count().max(1)).sum();
    let span = end.saturating_sub(start);
    let mut t = start;
    toks.iter()
        .map(|tok| {
            let w = tok.trim().chars().count().max(1) as u64;
            let d = span * w / total.max(1) as u64;
            let word = Word { start_ms: t, end_ms: t + d, text: tok.to_string() };
            t += d;
            word
        })
        .collect()
}

pub fn looks_synced(s: &str) -> bool {
    s.lines().any(|l| {
        let l = l.trim_start();
        l.starts_with('[') && l[1..].find(']').map_or(false, |e| parse_ts(&l[1..1 + e]).is_some())
    })
}

// ---------------- LRCLIB ----------------

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LrclibRecord {
    pub id: i64,
    pub track_name: Option<String>,
    pub artist_name: Option<String>,
    pub album_name: Option<String>,
    pub duration: Option<f64>,
    pub instrumental: Option<bool>,
    pub plain_lyrics: Option<String>,
    pub synced_lyrics: Option<String>,
}

pub struct LrclibClient {
    agent: ureq::Agent,
}

impl Default for LrclibClient {
    fn default() -> Self {
        Self {
            agent: ureq::AgentBuilder::new()
                .timeout(Duration::from_secs(8))
                .user_agent(USER_AGENT)
                .build(),
        }
    }
}

impl LrclibClient {
    pub fn get(&self, title: &str, artist: &str, album: &str, duration_s: u64) -> Option<LrclibRecord> {
        let mut req = self
            .agent
            .get(&format!("{LRCLIB}/get"))
            .query("track_name", title)
            .query("artist_name", artist)
            .query("duration", &duration_s.to_string());
        if !album.is_empty() {
            req = req.query("album_name", album);
        }
        req.call().ok()?.into_json().ok()
    }

    pub fn search(&self, title: &str, artist: &str, duration_s: u64) -> Option<LrclibRecord> {
        let list: Vec<LrclibRecord> = self
            .agent
            .get(&format!("{LRCLIB}/search"))
            .query("track_name", title)
            .query("artist_name", artist)
            .call()
            .ok()?
            .into_json()
            .ok()?;
        list.into_iter()
            .filter(|r| r.synced_lyrics.is_some() || r.plain_lyrics.is_some())
            .min_by_key(|r| {
                let d = (r.duration.unwrap_or(0.0) - duration_s as f64).abs() as i64;
                // prefer synced: penalise plain-only results
                d + if r.synced_lyrics.is_some() { 0 } else { 1000 }
            })
            .filter(|r| (r.duration.unwrap_or(0.0) - duration_s as f64).abs() < 10.0)
    }
}

// ---------------- resolver ----------------

fn now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() as i64
}

fn to_lyrics(synced: Option<String>, plain: Option<String>, dur: u64) -> Lyrics {
    if let Some(s) = synced.filter(|s| !s.trim().is_empty()) {
        let lines = parse_lrc(&s, Some(dur));
        if !lines.is_empty() {
            return Lyrics::Synced(lines);
        }
    }
    match plain.filter(|p| !p.trim().is_empty()) {
        Some(p) => Lyrics::Plain(p),
        None => Lyrics::None,
    }
}

fn sidecar(path: &Path) -> Option<(Option<String>, Option<String>)> {
    let lrc = path.with_extension("lrc");
    if let Ok(s) = std::fs::read_to_string(&lrc) {
        return Some((Some(s), None));
    }
    let txt = path.with_extension("txt");
    std::fs::read_to_string(txt).ok().map(|s| (None, Some(s)))
}

fn embedded(path: &Path) -> Option<String> {
    use lofty::file::TaggedFileExt;
    use lofty::tag::ItemKey;
    let f = lofty::read_from_path(path).ok()?;
    let t = f.primary_tag().or_else(|| f.first_tag())?;
    t.get_string(&ItemKey::Lyrics).map(str::to_owned)
}

/// Resolve lyrics for a track id. `online` = allow LRCLIB requests.
pub fn resolve(db: &Db, client: Option<&LrclibClient>, track_id: i64) -> Result<Lyrics> {
    let Some(t) = db.track(track_id)? else { return Ok(Lyrics::None) };
    let dur = t.duration_ms as u64;

    if let Some((source, synced, plain)) = db.cached_lyrics(track_id)? {
        let stale_negative = source == "none"
            && db
                .conn
                .query_row("SELECT fetched_at FROM lyrics WHERE track_id=?1", [track_id], |r| r.get::<_, i64>(0))
                .map(|f| now() - f > NEGATIVE_TTL_SECS)
                .unwrap_or(true);
        if !stale_negative {
            return Ok(to_lyrics(synced, plain, dur));
        }
    }

    let path = Path::new(&t.path);
    if let Some((s, p)) = sidecar(path) {
        db.store_lyrics(track_id, "sidecar", s.as_deref(), p.as_deref(), now())?;
        return Ok(to_lyrics(s, p, dur));
    }
    if let Some(e) = embedded(path) {
        let (s, p) = if looks_synced(&e) { (Some(e), None) } else { (None, Some(e)) };
        db.store_lyrics(track_id, "embedded", s.as_deref(), p.as_deref(), now())?;
        return Ok(to_lyrics(s, p, dur));
    }

    if let Some(c) = client {
        let secs = dur / 1000;
        let album = t.album.clone().unwrap_or_default();
        let rec = c
            .get(&t.title, &t.artist, &album, secs)
            .filter(|r| r.synced_lyrics.is_some() || r.plain_lyrics.is_some())
            .or_else(|| c.search(&t.title, &t.artist, secs));
        match rec {
            Some(r) => {
                db.store_lyrics(track_id, "lrclib", r.synced_lyrics.as_deref(), r.plain_lyrics.as_deref(), now())?;
                return Ok(to_lyrics(r.synced_lyrics, r.plain_lyrics, dur));
            }
            None => db.store_lyrics(track_id, "none", None, None, now())?,
        }
    }
    Ok(Lyrics::None)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timestamps() {
        assert_eq!(parse_ts("01:02.5"), Some(62_500));
        assert_eq!(parse_ts("01:02.50"), Some(62_500));
        assert_eq!(parse_ts("01:02.505"), Some(62_505));
        assert_eq!(parse_ts("00:07"), Some(7_000));
    }

    #[test]
    fn line_synced_gets_interpolated_words() {
        let l = parse_lrc("[ti:x]\n[00:01.00]Olá mundo\n[00:03.00]Tchau", Some(5000));
        assert_eq!(l.len(), 2);
        assert_eq!(l[0].end_ms, 3000);
        assert_eq!(l[0].words.len(), 2);
        assert!(!l[0].word_synced);
        assert_eq!(l[0].words[0].start_ms, 1000);
        assert_eq!(l[1].end_ms, 5000);
    }

    #[test]
    fn enhanced_lrc_words() {
        let l = parse_lrc("[00:10.00]<00:10.00>Hel<00:10.50>lo <00:11.00>world\n[00:13.00]x", None);
        assert!(l[0].word_synced);
        assert_eq!(l[0].text, "Hello world");
        assert_eq!(
            l[0].words.iter().map(|w| (w.start_ms, w.end_ms)).collect::<Vec<_>>(),
            vec![(10_000, 10_500), (10_500, 11_000), (11_000, 13_000)]
        );
    }

    #[test]
    fn repeated_stamps_and_offset() {
        let l = parse_lrc("[offset:500]\n[00:05.00][00:20.00]Refrão", Some(30_000));
        assert_eq!(l.len(), 2);
        assert_eq!(l[0].start_ms, 4_500);
        assert_eq!(l[1].start_ms, 19_500);
        assert_eq!(Lyrics::line_at(&l, 10_000), Some(0));
        assert_eq!(Lyrics::line_at(&l, 1_000), None);
    }
}
