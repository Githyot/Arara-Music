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
    /// Who sings it: 0 = main voice (left), 1 = another singer (right),
    /// 2 = background vocals "(…)" (small, under the line before).
    pub voice: u8,
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
                voice: 0,
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
            // Words are sung at speech pace, not stretched over an instrumental gap.
            let chars = l.text.chars().filter(|c| c.is_alphanumeric()).count() as u64;
            let sung = (chars * 85 + 700).max(1200);
            l.words = interpolate_words(&l.text, l.start_ms, next.min(l.start_ms + sung));
        }
    }
    assign_voices(&mut lines);
    lines
}

/// Duets: "v1:"/"v2:" markers (Apple-style exports) or "Name: words" prefixes that
/// repeat through the song. The first singer stays on the left, the others go to
/// the right; a voice carries over until the next marker. Lines fully in
/// parentheses are background vocals.
fn assign_voices(lines: &mut [Line]) {
    fn prefix(text: &str) -> Option<(String, usize)> {
        let i = text.find(':')?;
        let name = text[..i].trim();
        let ok = !name.is_empty() && name.chars().count() <= 24 && name.split_whitespace().count() <= 3
            && !name.chars().any(|c| c.is_ascii_digit() && !name.to_lowercase().starts_with('v'));
        ok.then(|| (name.to_lowercase(), i + 1))
    }
    use std::collections::HashMap;
    let mut counts: HashMap<String, usize> = HashMap::new();
    for l in lines.iter() {
        if let Some((n, _)) = prefix(&l.text) {
            *counts.entry(n).or_default() += 1;
        }
    }
    let is_marker = |n: &str| matches!(n, "v1" | "v2" | "v3") || counts.get(n).copied().unwrap_or(0) >= 2;
    let mut order: Vec<String> = Vec::new();
    let mut voice = 0u8;
    for l in lines.iter_mut() {
        if let Some((n, cut)) = prefix(&l.text).filter(|(n, _)| is_marker(n)) {
            voice = match n.as_str() {
                "v1" => 0,
                "v2" | "v3" => 1,
                _ => {
                    if !order.contains(&n) {
                        order.push(n.clone());
                    }
                    if order[0] == n { 0 } else { 1 }
                }
            };
            // Drop the marker from the text and from the first word(s).
            let mut left = cut;
            l.text = l.text[cut..].trim_start().to_string();
            l.words.retain_mut(|w| {
                let wl = w.text.len();
                if left == 0 {
                    return true;
                }
                if wl <= left {
                    left -= wl;
                    false
                } else {
                    w.text = w.text[left..].trim_start().to_string();
                    left = 0;
                    !w.text.is_empty()
                }
            });
        }
        let t = l.text.trim();
        l.voice = if t.len() > 2 && t.starts_with('(') && t.ends_with(')') { 2 } else { voice };
    }
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
    /// Exact lookup. Ok(None) = LRCLIB doesn't know the song; Err = network/server problem.
    pub fn get(&self, title: &str, artist: &str, album: &str, duration_s: u64) -> std::result::Result<Option<LrclibRecord>, String> {
        let mut req = self
            .agent
            .get(&format!("{LRCLIB}/get"))
            .query("track_name", title)
            .query("artist_name", artist)
            .query("duration", &duration_s.to_string());
        if !album.is_empty() {
            req = req.query("album_name", album);
        }
        match req.call() {
            Ok(r) => Ok(r.into_json::<LrclibRecord>().ok().filter(|r| r.synced_lyrics.is_some() || r.plain_lyrics.is_some())),
            Err(ureq::Error::Status(404, _)) => Ok(None),
            Err(e) => Err(e.to_string()),
        }
    }

    /// Fuzzy search; picks the closest duration, preferring synced lyrics.
    pub fn search(&self, title: &str, artist: &str, duration_s: u64) -> std::result::Result<Option<LrclibRecord>, String> {
        let mut req = self.agent.get(&format!("{LRCLIB}/search"));
        req = if artist.is_empty() { req.query("q", title) } else { req.query("track_name", title).query("artist_name", artist) };
        let list: Vec<LrclibRecord> = match req.call() {
            Ok(r) => r.into_json().unwrap_or_default(),
            Err(ureq::Error::Status(404, _)) => vec![],
            Err(e) => return Err(e.to_string()),
        };
        Ok(list
            .into_iter()
            .filter(|r| r.synced_lyrics.is_some() || r.plain_lyrics.is_some())
            .filter(|r| duration_s == 0 || (r.duration.unwrap_or(0.0) - duration_s as f64).abs() < 10.0)
            .min_by_key(|r| {
                let d = (r.duration.unwrap_or(0.0) - duration_s as f64).abs() as i64;
                // prefer synced: penalise plain-only results
                d + if r.synced_lyrics.is_some() { 0 } else { 1000 }
            }))
    }

    /// Tries the exact match, then cleaned-up titles/artists ("Song (feat. X)" → "Song",
    /// "A, B & C" → "A"), then a free-text search. Err only if every attempt failed on the network.
    pub fn find(&self, title: &str, artist: &str, album: &str, duration_s: u64) -> std::result::Result<Option<LrclibRecord>, String> {
        let clean_t = clean_title(title);
        let main_a = main_artist(artist);
        let mut attempts: Vec<Box<dyn Fn() -> std::result::Result<Option<LrclibRecord>, String> + '_>> = vec![
            Box::new(|| self.get(title, artist, album, duration_s)),
            Box::new(|| self.search(title, artist, duration_s)),
        ];
        if clean_t != title || main_a != artist {
            attempts.push(Box::new(|| self.get(&clean_t, &main_a, "", duration_s)));
            attempts.push(Box::new(|| self.search(&clean_t, &main_a, duration_s)));
        }
        attempts.push(Box::new(|| self.search(&format!("{main_a} {clean_t}"), "", duration_s)));
        let mut last_err = None;
        let mut any_ok = false;
        let mut plain: Option<LrclibRecord> = None;
        for a in attempts {
            match a() {
                Ok(Some(r)) if r.synced_lyrics.is_some() => return Ok(Some(r)),
                Ok(Some(r)) => {
                    any_ok = true;
                    plain.get_or_insert(r);
                }
                Ok(None) => any_ok = true,
                Err(e) => last_err = Some(e),
            }
        }
        match (plain, any_ok, last_err) {
            (Some(r), _, _) => Ok(Some(r)),
            (None, false, Some(e)) => Err(e),
            _ => Ok(None),
        }
    }
}

/// "Baile 01 (feat. A, B)" → "Baile 01"; also drops "[Remastered]", "- Remastered 2011",
/// "(Official Video)". Version markers that change the recording — "(Remix)", "(Ao Vivo)",
/// "(Acoustic)" — are kept, or a remix would get the original's timings.
pub fn clean_title(t: &str) -> String {
    const NOISE: [&str; 12] = [
        "feat", "ft.", "with ", "remaster", "explicit", "clean", "official", "video", "lyric", "bonus", "deluxe", "mono",
    ];
    let mut out = String::new();
    let mut rest = t;
    while let Some(a) = rest.find(['(', '[']) {
        let close = if rest.as_bytes()[a] == b'(' { ')' } else { ']' };
        let Some(len) = rest[a..].find(close) else { break };
        let inner = rest[a + 1..a + len].to_lowercase();
        out.push_str(&rest[..a]);
        if !NOISE.iter().any(|n| inner.contains(n)) {
            out.push_str(&rest[a..=a + len]);
        }
        rest = &rest[a + len + 1..];
    }
    out.push_str(rest);
    let lower = out.to_lowercase();
    for cut in [" - remaster", " - single", " - radio edit", " feat.", " ft.", " featuring "] {
        if let Some(i) = lower.find(cut) {
            out.truncate(i);
            break;
        }
    }
    let s = out.split_whitespace().collect::<Vec<_>>().join(" ");
    if s.is_empty() { t.trim().to_string() } else { s }
}

/// "1Kilo, Knust & Pelé" / "A feat. B" → "1Kilo"
pub fn main_artist(a: &str) -> String {
    let lower = a.to_lowercase();
    let mut end = a.len();
    for sep in [",", " & ", " feat", " ft.", " x ", " e ", ";", "/"] {
        if let Some(i) = lower.find(sep) {
            end = end.min(i);
        }
    }
    let s = a[..end].trim();
    if s.is_empty() { a.trim().to_string() } else { s.to_string() }
}

// ---------------- writing LRC & publishing ----------------

pub fn format_ts(ms: u64) -> String {
    format!("{:02}:{:02}.{:02}", ms / 60_000, (ms / 1000) % 60, (ms % 1000) / 10)
}

/// Build line-synced LRC from (start_ms, text) pairs.
pub fn to_lrc(lines: &[(u64, String)]) -> String {
    let mut out = String::new();
    for (t, text) in lines {
        out.push_str(&format!("[{}]{}\n", format_ts(*t), text));
    }
    out
}

/// Strip timestamps, keeping only the words (LRCLIB wants both forms).
pub fn lrc_to_plain(lrc: &str) -> String {
    parse_lrc(lrc, None).into_iter().map(|l| l.text).collect::<Vec<_>>().join("\n")
}

/// LRCLIB's anti-spam proof of work: find `nonce` with sha256(prefix+nonce) <= target.
pub fn solve_challenge(prefix: &str, target_hex: &str) -> Option<String> {
    use sha2::{Digest, Sha256};
    let target: Vec<u8> = (0..target_hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&target_hex[i..i + 2], 16))
        .collect::<std::result::Result<_, _>>()
        .ok()?;
    for nonce in 0u64.. {
        let n = nonce.to_string();
        let mut h = Sha256::new();
        h.update(prefix.as_bytes());
        h.update(n.as_bytes());
        if h.finalize().as_slice() <= target.as_slice() {
            return Some(n);
        }
        if nonce > 500_000_000 {
            return None;
        }
    }
    None
}

#[derive(Debug, Deserialize)]
struct Challenge {
    prefix: String,
    target: String,
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PublishRequest {
    pub track_name: String,
    pub artist_name: String,
    pub album_name: String,
    pub duration: u64,
    pub plain_lyrics: String,
    pub synced_lyrics: String,
}

impl LrclibClient {
    /// Publish lyrics to LRCLIB (takes a few seconds: solves the proof-of-work challenge).
    pub fn publish(&self, req: &PublishRequest) -> std::result::Result<(), String> {
        let ch: Challenge = self
            .agent
            .post(&format!("{LRCLIB}/request-challenge"))
            .call()
            .map_err(|e| e.to_string())?
            .into_json()
            .map_err(|e| e.to_string())?;
        let nonce = solve_challenge(&ch.prefix, &ch.target).ok_or("desafio sem solução")?;
        self.agent
            .post(&format!("{LRCLIB}/publish"))
            .set("X-Publish-Token", &format!("{}:{}", ch.prefix, nonce))
            .send_json(req)
            .map_err(|e| e.to_string())?;
        Ok(())
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

/// Tracks that still need a lyrics lookup (never tried, or a "none" answer older than
/// the negative TTL), most-played and recently played first.
pub fn pending_tracks(db: &Db) -> Result<Vec<i64>> {
    let mut st = db.conn.prepare(
        "SELECT t.id FROM tracks t LEFT JOIN lyrics l ON l.track_id = t.id
         WHERE l.track_id IS NULL OR (l.source = 'none' AND l.fetched_at < ?1)
         ORDER BY t.play_count DESC, COALESCE(t.last_played, 0) DESC, t.starred DESC, t.album_id, t.disc_no, t.track_no",
    )?;
    let rows = st.query_map([now() - NEGATIVE_TTL_SECS], |r| r.get(0))?;
    Ok(rows.flatten().collect())
}

/// Resolve lyrics for a track id. `online` = allow LRCLIB requests.
pub fn resolve(db: &Db, client: Option<&LrclibClient>, track_id: i64) -> Result<Lyrics> {
    let Some(t) = db.track(track_id)? else { return Ok(Lyrics::None) };
    let dur = t.duration_ms as u64;

    if let Some((source, synced, plain)) = db.cached_lyrics(track_id)? {
        // A "none" answer, or words without timings, is looked up online again after a while.
        let ttl = if source == "none" { NEGATIVE_TTL_SECS } else { 3600 };
        let retry = source != "user"
            && (source == "none" || synced.is_none())
            && client.is_some()
            && db
                .conn
                .query_row("SELECT fetched_at FROM lyrics WHERE track_id=?1", [track_id], |r| r.get::<_, i64>(0))
                .map(|f| now() - f > ttl)
                .unwrap_or(true);
        if !retry {
            return Ok(to_lyrics(synced, plain, dur));
        }
    }

    // Local lyrics first. Plain-only local lyrics are kept, but we still look online for a synced version.
    let path = Path::new(&t.path);
    let local = sidecar(path).map(|(s, p)| ("sidecar", s, p)).or_else(|| {
        embedded(path).map(|e| if looks_synced(&e) { ("embedded", Some(e), None) } else { ("embedded", None, Some(e)) })
    });
    if let Some((src, Some(s), p)) = &local {
        db.store_lyrics(track_id, src, Some(s), p.as_deref(), now())?;
        return Ok(to_lyrics(Some(s.clone()), p.clone(), dur));
    }

    if let Some(c) = client {
        let album = t.album.clone().unwrap_or_default();
        match c.find(&t.title, &t.artist, &album, dur / 1000) {
            Ok(Some(r)) if r.synced_lyrics.is_some() || local.is_none() => {
                db.store_lyrics(track_id, "lrclib", r.synced_lyrics.as_deref(), r.plain_lyrics.as_deref(), now())?;
                return Ok(to_lyrics(r.synced_lyrics, r.plain_lyrics, dur));
            }
            Ok(_) => {
                if local.is_none() {
                    db.store_lyrics(track_id, "none", None, None, now())?;
                }
            }
            // Offline or LRCLIB down: don't remember a "no lyrics" answer, try again next time.
            // Offline: show local words but don't cache them, so LRCLIB is asked next time.
            Err(e) => {
                log::info!("LRCLIB unreachable for track {track_id}: {e}");
                if let Some((_, s, p)) = local {
                    return Ok(to_lyrics(s, p, dur));
                }
            }
        }
    }
    if let Some((src, s, p)) = local {
        db.store_lyrics(track_id, src, s.as_deref(), p.as_deref(), now())?;
        return Ok(to_lyrics(s, p, dur));
    }
    Ok(Lyrics::None)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_and_rereads_lrc() {
        let lrc = to_lrc(&[(1_230, "Olá".into()), (65_400, "mundo".into())]);
        assert_eq!(lrc, "[00:01.23]Olá\n[01:05.40]mundo\n");
        let l = parse_lrc(&lrc, None);
        assert_eq!((l[1].start_ms, l[1].text.as_str()), (65_400, "mundo"));
        assert_eq!(lrc_to_plain(&lrc), "Olá\nmundo");
    }

    #[test]
    fn proof_of_work() {
        use sha2::{Digest, Sha256};
        // easy target: first byte must be 0x0f or lower (~1/16 chance per try)
        let target = format!("0f{}", "ff".repeat(31));
        let n = solve_challenge("arara", &target).unwrap();
        let h = Sha256::digest(format!("arara{n}").as_bytes());
        assert!(h[0] <= 0x0f);
    }

    #[test]
    fn cleans_titles_and_artists() {
        assert_eq!(clean_title("Baile 01 (feat. Pablo Martins, Knust & Funkeiro)"), "Baile 01");
        assert_eq!(clean_title("Help! - Remastered 2009"), "Help!");
        assert_eq!(clean_title("(Intro)"), "(Intro)");
        assert_eq!(clean_title("Diamonds (Remix) [feat. Kanye West]"), "Diamonds (Remix)");
        assert_eq!(clean_title("Song (Official Video) (Ao Vivo)"), "Song (Ao Vivo)");
        assert_eq!(main_artist("1Kilo, Knust & Pelé"), "1Kilo");
        assert_eq!(main_artist("Anitta feat. X"), "Anitta");
        assert_eq!(main_artist("Tim Maia"), "Tim Maia");
    }

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
    fn duet_voices() {
        let l = parse_lrc(
            "[00:01.00]Rihanna: Shine bright\n[00:03.00]like a diamond\n[00:05.00]Kanye: Yeah\n[00:07.00](Ooh)\n[00:09.00]Rihanna: Again\n[00:11.00]Kanye: Ok",
            Some(13_000),
        );
        assert_eq!(l.iter().map(|x| x.voice).collect::<Vec<_>>(), vec![0, 0, 1, 2, 0, 1]);
        assert_eq!(l[0].text, "Shine bright");
        assert_eq!(l[0].words.iter().map(|w| w.text.trim()).collect::<Vec<_>>(), vec!["Shine", "bright"]);
        // A one-off "Note: ..." is not a singer.
        let l = parse_lrc("[00:01.00]Note: hi\n[00:02.00]x", None);
        assert_eq!((l[0].voice, l[0].text.as_str()), (0, "Note: hi"));
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
