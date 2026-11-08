//! Repeated songs: the same recording more than once in the library (a FLAC
//! and an MP3 of the same album, a local file and its copy on a server…).
//!
//! Only the best copy shows up in the app; the others get `tracks.dup_of` set
//! to the id of the copy that stays. Nothing is deleted from disk. The pass
//! runs after every scan, server sync and edit, and whenever the preference
//! (`pref:hidedupes`, on by default) or a hand-picked copy changes.
//!
//! Two tracks are copies when artist, album and title match after
//! normalisation (case, accents, punctuation), their lengths differ by at most
//! [`TOLERANCE_MS`], and they are not obviously two different tracks of one
//! record (different discs, or different track numbers in the same folder).

use rusqlite::{params, Connection};
use std::collections::HashMap;

use crate::db::Db;
use crate::Result;

/// Two copies of one song can differ a little in length (encoder padding,
/// a different rip); two different songs with the same name rarely this close.
pub const TOLERANCE_MS: i64 = 3_000;

#[derive(Debug, Clone)]
pub struct Copy {
    pub id: i64,
    pub path: String,
    pub format: Option<String>,
    pub sample_rate: Option<i64>,
    pub bit_depth: Option<i64>,
    pub bitrate: Option<i64>,
    pub size: i64,
    pub duration_ms: i64,
    disc: i64,
    track: i64,
}

impl Copy {
    pub fn lossless(&self) -> bool {
        matches!(self.format.as_deref().unwrap_or(""), "FLAC" | "ALAC" | "WAV" | "AIFF" | "WavPack" | "APE")
    }

    pub fn is_remote(&self) -> bool {
        self.path.starts_with(crate::remote::PREFIX)
    }

    /// kbit/s from the tag, or estimated from file size and length.
    pub fn kbps(&self) -> i64 {
        match self.bitrate.filter(|b| *b > 0) {
            Some(b) => b,
            None if self.duration_ms > 0 && self.size > 0 => self.size * 8 / self.duration_ms,
            None => 0,
        }
    }

    /// Bigger is better: lossless first (more bits, then higher rate), then
    /// lossy by bitrate; a local file beats a server copy of equal quality.
    fn rank(&self) -> (u8, i64, i64, i64, u8, i64, i64) {
        let rate = self.sample_rate.unwrap_or(0);
        let (a, b, c) = if self.lossless() {
            (self.bit_depth.unwrap_or(16), rate, self.kbps())
        } else {
            (self.kbps(), rate, 0)
        };
        (self.lossless() as u8, a, b, c, !self.is_remote() as u8, self.size, -self.id)
    }

    /// "FLAC · 16 bits · 44,1 kHz" / "MP3 · 320 kbps".
    pub fn quality(&self) -> String {
        let mut parts = vec![];
        if let Some(f) = self.format.as_deref().filter(|f| !f.is_empty()) {
            parts.push(f.to_string());
        }
        if self.lossless() {
            if let Some(b) = self.bit_depth.filter(|b| *b > 0) {
                parts.push(format!("{b} bits"));
            }
        }
        if let Some(r) = self.sample_rate.filter(|r| *r > 0) {
            let k = r as f64 / 1000.0;
            parts.push(if k.fract() == 0.0 { format!("{k:.0} kHz") } else { format!("{k:.1} kHz").replace('.', ",") });
        }
        if !self.lossless() && self.kbps() > 0 {
            parts.push(format!("{} kbps", self.kbps()));
        }
        parts.join(" · ")
    }

    fn dir(&self) -> &str {
        self.path.rsplit_once('/').map_or("", |(d, _)| d)
    }
}

/// One song with its copies, best (or hand-picked) first.
#[derive(Debug, Clone)]
pub struct Group {
    pub key: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub album_id: Option<i64>,
    /// `copies[0]` is the one shown in the app.
    pub copies: Vec<Copy>,
    /// The user chose the kept copy (instead of the best quality).
    pub picked: bool,
}

/// Lower case, accents dropped, only letters and digits ("Don't Stop" == "dont stop").
pub fn norm(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars().flat_map(char::to_lowercase) {
        let c = match c {
            'á' | 'à' | 'â' | 'ã' | 'ä' | 'å' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'í' | 'ì' | 'î' | 'ï' => 'i',
            'ó' | 'ò' | 'ô' | 'õ' | 'ö' | 'ø' => 'o',
            'ú' | 'ù' | 'û' | 'ü' => 'u',
            'ç' => 'c',
            'ñ' => 'n',
            c => c,
        };
        if c.is_alphanumeric() {
            out.push(c);
        }
    }
    out
}

pub fn enabled(c: &Connection) -> bool {
    c.query_row("SELECT v FROM kv WHERE k = 'pref:hidedupes'", [], |r| r.get::<_, String>(0))
        .map_or(true, |v| v != "0")
}

fn could_be_copies(a: &Copy, b: &Copy) -> bool {
    if a.duration_ms > 0 && b.duration_ms > 0 && (a.duration_ms - b.duration_ms).abs() > TOLERANCE_MS {
        return false;
    }
    if a.disc > 0 && b.disc > 0 && a.disc != b.disc {
        return false;
    }
    // Same folder, different track numbers: two songs that share a name
    // ("Intro", "Interlude") on one record, not two copies.
    !(a.track > 0 && b.track > 0 && a.track != b.track && a.dir() == b.dir())
}

/// Every song that has more than one copy, whether or not hiding is on.
pub fn find_groups(c: &Connection) -> Result<Vec<Group>> {
    struct Meta {
        title: String,
        artist: String,
        album: String,
        album_id: Option<i64>,
    }
    let mut buckets: HashMap<String, Vec<(Copy, Meta)>> = HashMap::new();
    {
        let mut st = c.prepare(
            "SELECT t.id, t.path, t.title, t.artist, COALESCE(a.title, ''), t.album_id,
                    COALESCE((SELECT name FROM artists WHERE id = a.artist_id), t.artist),
                    t.format, t.sample_rate, t.bit_depth, t.bitrate, t.size, t.duration_ms,
                    COALESCE(t.disc_no, 0), COALESCE(t.track_no, 0)
             FROM tracks t LEFT JOIN albums a ON a.id = t.album_id",
        )?;
        let rows = st.query_map([], |r| {
            let album: String = r.get(4)?;
            let album_artist: String = r.get(6)?;
            let title: String = r.get(2)?;
            let copy = Copy {
                id: r.get(0)?,
                path: r.get(1)?,
                format: r.get(7)?,
                sample_rate: r.get(8)?,
                bit_depth: r.get(9)?,
                bitrate: r.get(10)?,
                size: r.get(11)?,
                duration_ms: r.get(12)?,
                disc: r.get(13)?,
                track: r.get(14)?,
            };
            let key = format!("{}\u{1}{}\u{1}{}", norm(&album_artist), norm(&album), norm(&title));
            Ok((key, copy, Meta { title, artist: album_artist, album, album_id: r.get(5)? }))
        })?;
        for row in rows.flatten() {
            let (key, copy, meta) = row;
            // A title made only of symbols normalises to nothing: never group those.
            if key.ends_with('\u{1}') {
                continue;
            }
            buckets.entry(key).or_default().push((copy, meta));
        }
    }
    let picks: HashMap<String, String> = {
        let mut st = c.prepare("SELECT substr(k, 9), v FROM kv WHERE k LIKE 'dupkeep:%'")?;
        let rows = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?;
        rows.flatten().collect()
    };
    let mut out = vec![];
    for (key, mut items) in buckets {
        if items.len() < 2 {
            continue;
        }
        // Split by length: chain songs whose durations are within tolerance.
        items.sort_by_key(|(c, _)| (c.duration_ms, c.id));
        let mut clusters: Vec<Vec<(Copy, Meta)>> = vec![];
        for it in items {
            let fits = clusters.last().is_some_and(|cl| cl.iter().all(|(c, _)| could_be_copies(c, &it.0)));
            if fits {
                clusters.last_mut().unwrap().push(it);
            } else {
                clusters.push(vec![it]);
            }
        }
        for cl in clusters.into_iter().filter(|cl| cl.len() > 1) {
            let mut copies: Vec<Copy> = cl.iter().map(|(c, _)| c.clone()).collect();
            copies.sort_by(|a, b| b.rank().cmp(&a.rank()));
            let mut picked = false;
            if let Some(p) = picks.get(&key) {
                if let Some(i) = copies.iter().position(|c| &c.path == p) {
                    if i > 0 {
                        let c = copies.remove(i);
                        copies.insert(0, c);
                    }
                    picked = true;
                }
            }
            let kept = copies[0].id;
            let meta = &cl.iter().find(|(c, _)| c.id == kept).unwrap().1;
            out.push(Group {
                key: key.clone(),
                title: meta.title.clone(),
                artist: meta.artist.clone(),
                album: meta.album.clone(),
                album_id: meta.album_id,
                copies,
                picked,
            });
        }
    }
    out.sort_by(|a, b| {
        crate::natural::natural_cmp(&a.artist, &b.artist)
            .then_with(|| crate::natural::natural_cmp(&a.album, &b.album))
            .then_with(|| crate::natural::natural_cmp(&a.title, &b.title))
    });
    Ok(out)
}

/// Recompute which copies are hidden. Stars move to the copy that stays, so
/// a favourite never disappears with its hidden twin. Returns how many
/// copies are hidden now. Runs on the caller's transaction, if any.
pub fn mark(c: &Connection) -> Result<usize> {
    let groups = if enabled(c) { find_groups(c)? } else { vec![] };
    let mut want: HashMap<i64, i64> = HashMap::new();
    for g in &groups {
        for copy in &g.copies[1..] {
            want.insert(copy.id, g.copies[0].id);
        }
    }
    let now: HashMap<i64, i64> = {
        let mut st = c.prepare("SELECT id, dup_of FROM tracks WHERE dup_of IS NOT NULL")?;
        let rows = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?;
        rows.flatten().collect()
    };
    if now == want {
        return Ok(want.len());
    }
    {
        let tx = c;
        let mut clear = tx.prepare("UPDATE tracks SET dup_of = NULL WHERE id = ?1")?;
        for id in now.keys().filter(|id| !want.contains_key(id)) {
            clear.execute([id])?;
        }
        let mut set = tx.prepare("UPDATE tracks SET dup_of = ?2 WHERE id = ?1")?;
        let mut star = tx.prepare(
            "UPDATE tracks SET starred = 1 WHERE id = ?2 AND starred = 0 AND (SELECT starred FROM tracks WHERE id = ?1) = 1",
        )?;
        for (id, kept) in &want {
            if now.get(id) != Some(kept) {
                set.execute(params![id, kept])?;
                star.execute(params![id, kept])?;
            }
        }
    }
    Ok(want.len())
}

impl Db {
    /// Show `track_id` instead of the other copies of its song.
    pub fn keep_copy(&self, track_id: i64) -> Result<()> {
        let path: String = self.conn.query_row("SELECT path FROM tracks WHERE id = ?1", [track_id], |r| r.get(0))?;
        let _w = crate::db::WRITER.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(g) = find_groups(&self.conn)?.into_iter().find(|g| g.copies.iter().any(|c| c.id == track_id)) {
            self.set_kv(&format!("dupkeep:{}", g.key), &path)?;
        }
        self.mark_in_tx()?;
        Ok(())
    }

    /// Go back to keeping the best copy of every song.
    pub fn forget_kept_copies(&self) -> Result<()> {
        let _w = crate::db::WRITER.lock().unwrap_or_else(|e| e.into_inner());
        self.conn.execute("DELETE FROM kv WHERE k LIKE 'dupkeep:%'", [])?;
        self.mark_in_tx()?;
        Ok(())
    }

    /// Re-run the pass (after the preference changed).
    pub fn mark_duplicates(&self) -> Result<usize> {
        let _w = crate::db::WRITER.lock().unwrap_or_else(|e| e.into_inner());
        self.mark_in_tx()
    }

    fn mark_in_tx(&self) -> Result<usize> {
        let tx = self.conn.unchecked_transaction()?;
        let n = mark(&tx)?;
        tx.commit()?;
        Ok(n)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::NewTrack;

    #[allow(clippy::too_many_arguments)]
    fn add(db: &Db, path: &str, title: &str, album: &str, format: &str, bits: Option<u8>, bitrate: Option<u32>, dur: i64, track: u32) {
        let t = NewTrack {
            path,
            mtime: 1,
            size: 1000,
            title,
            artist: "Arctic Monkeys",
            album_artist: "Arctic Monkeys",
            album: Some(album),
            track_no: Some(track),
            disc_no: None,
            year: Some(2007),
            duration_ms: dur,
            track_gain: None,
            album_gain: None,
            cover_hash: None,
            genre: None,
            composer: None,
            format: Some(format),
            sample_rate: Some(44_100),
            bit_depth: bits,
            bitrate,
            explicit: None,
            art_hash: None,
            folder_art: None,
        };
        crate::db::upsert_track(&db.conn, &t, 1).unwrap();
    }

    fn id(db: &Db, path: &str) -> i64 {
        db.conn.query_row("SELECT id FROM tracks WHERE path = ?1", [path], |r| r.get(0)).unwrap()
    }

    #[test]
    fn keeps_the_lossless_copy() {
        let db = Db::open_in_memory().unwrap();
        add(&db, "/m/flac/01.flac", "Brianstorm", "Favourite Worst Nightmare", "FLAC", Some(16), None, 170_000, 1);
        add(&db, "/m/mp3/01.mp3", "Brianstorm", "Favourite Worst Nightmare", "MP3", None, Some(320), 170_400, 1);
        add(&db, "/m/flac/02.flac", "Teddy Picker", "Favourite Worst Nightmare", "FLAC", Some(16), None, 161_000, 2);
        add(&db, "/m/mp3/02.mp3", "Teddy Picker", "Favourite Worst Nightmare", "MP3", None, Some(320), 161_000, 2);
        add(&db, "/m/flac/03.flac", "D Is for Dangerous", "Favourite Worst Nightmare", "FLAC", Some(16), None, 135_000, 3);
        db.set_starred(id(&db, "/m/mp3/02.mp3"), true).unwrap();
        assert_eq!(mark(&db.conn).unwrap(), 2);
        let tracks = db.album_tracks(db.albums().unwrap()[0].id).unwrap();
        assert_eq!(tracks.len(), 3);
        assert!(tracks.iter().all(|t| t.format.as_deref() == Some("FLAC")));
        assert_eq!(db.albums().unwrap()[0].track_count, 3);
        // The star of the hidden MP3 moved to the FLAC.
        assert!(db.starred_tracks().unwrap().iter().any(|t| t.path == "/m/flac/02.flac"));
        assert_eq!(db.search("brianstorm", 10).unwrap().len(), 1);
        assert_eq!(db.counts().unwrap().0, 3);

        // The user prefers the MP3 of Brianstorm.
        db.keep_copy(id(&db, "/m/mp3/01.mp3")).unwrap();
        let tracks = db.album_tracks(db.albums().unwrap()[0].id).unwrap();
        assert!(tracks.iter().any(|t| t.path == "/m/mp3/01.mp3"));
        assert!(!tracks.iter().any(|t| t.path == "/m/flac/01.flac"));
        db.forget_kept_copies().unwrap();

        // Turned off: everything shows again.
        db.set_kv("pref:hidedupes", "0").unwrap();
        db.mark_duplicates().unwrap();
        assert_eq!(db.album_tracks(db.albums().unwrap()[0].id).unwrap().len(), 5);
        assert_eq!(find_groups(&db.conn).unwrap().len(), 2);
    }

    #[test]
    fn different_songs_with_one_name_stay() {
        let db = Db::open_in_memory().unwrap();
        // Two "Intro"s on one record, far apart in length or track number.
        add(&db, "/m/a/01.flac", "Intro", "Album", "FLAC", Some(16), None, 60_000, 1);
        add(&db, "/m/a/09.flac", "Intro", "Album", "FLAC", Some(16), None, 61_000, 9);
        add(&db, "/m/a/10.flac", "Interlude", "Album", "FLAC", Some(16), None, 60_000, 10);
        add(&db, "/m/b/10.mp3", "Interlude", "Album", "MP3", None, Some(128), 90_000, 10);
        assert_eq!(mark(&db.conn).unwrap(), 0);
        // Higher bitrate wins between two lossy copies.
        add(&db, "/m/c/x.mp3", "Song", "Other", "MP3", None, Some(128), 200_000, 1);
        add(&db, "/m/d/x.ogg", "Song", "Other", "Opus", None, Some(256), 199_000, 1);
        assert_eq!(mark(&db.conn).unwrap(), 1);
        let g = find_groups(&db.conn).unwrap();
        assert_eq!(g[0].copies[0].path, "/m/d/x.ogg");
        assert_eq!(norm("Don't Stop Me Nów!"), "dontstopmenow");
    }
}
