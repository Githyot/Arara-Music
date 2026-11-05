//! Incremental, parallel library scanner.
//!
//! Differences from Nocturne's approach:
//! * Only files whose (mtime, size) changed since the last scan are parsed.
//! * Tag parsing runs on a rayon pool; *writes* happen on one thread in a
//!   single transaction (SQLite is fastest that way).
//! * Embedded covers are decoded once **per album**, shrunk to a small JPEG
//!   thumbnail on disk, and never kept in RAM. The UI loads thumbnails lazily
//!   for visible items only.

use lofty::file::{AudioFile, TaggedFileExt};
use lofty::tag::{Accessor, ItemKey};
use rayon::prelude::*;
use rusqlite::params;
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::time::{Instant, SystemTime, UNIX_EPOCH};
use walkdir::WalkDir;

use crate::covers::CoverCache;
use crate::db::Db;
use crate::Result;

pub const AUDIO_EXTENSIONS: &[&str] = &[
    "mp3", "flac", "ogg", "oga", "opus", "m4a", "mp4", "aac", "wav", "wv", "ape", "aiff", "aif",
];

#[derive(Debug, Default, Clone)]
pub struct ScanStats {
    pub seen: usize,
    pub parsed: usize,
    pub unchanged: usize,
    pub removed: usize,
    pub failed: usize,
    pub covers_written: usize,
    pub elapsed_ms: u128,
}

/// Progress callback events (UI can show "Indexando 1200/5000").
#[derive(Debug, Clone)]
pub enum ScanEvent {
    Discovered(usize),
    Parsed { done: usize, total: usize },
    Finished(ScanStats),
}

struct Parsed {
    path: String,
    mtime: i64,
    size: i64,
    title: String,
    artist: String,
    album_artist: String,
    album: Option<String>,
    track_no: Option<u32>,
    disc_no: Option<u32>,
    year: Option<u32>,
    duration_ms: u64,
    track_gain: Option<f64>,
    album_gain: Option<f64>,
    /// Hash of the album thumbnail written by the worker (first track of each album only).
    cover_hash: Option<String>,
}

/// Which albums already have (or are getting) a cover, shared by the parser threads.
pub struct CoverClaims {
    albums: std::sync::Mutex<HashSet<(String, String)>>,
    dirs: std::sync::Mutex<HashSet<PathBuf>>,
}

impl CoverClaims {
    fn new(existing: HashSet<(String, String)>) -> Self {
        Self { albums: std::sync::Mutex::new(existing), dirs: Default::default() }
    }
    fn key(album: &str, artist: &str) -> (String, String) {
        let aa = if artist.is_empty() { "Artista desconhecido" } else { artist };
        (album.to_string(), aa.to_string())
    }
    fn has(&self, album: &str, artist: &str) -> bool {
        self.albums.lock().unwrap().contains(&Self::key(album, artist))
    }
    fn claim(&self, album: &str, artist: &str) -> bool {
        self.albums.lock().unwrap().insert(Self::key(album, artist))
    }
    fn first_visit(&self, dir: &Path) -> bool {
        self.dirs.lock().unwrap().insert(dir.to_path_buf())
    }
}

fn is_audio(p: &Path) -> bool {
    p.extension()
        .and_then(|e| e.to_str())
        .map(|e| AUDIO_EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
        .unwrap_or(false)
}

fn file_sig(p: &Path) -> Option<(i64, i64)> {
    let md = std::fs::metadata(p).ok()?;
    let mtime = md
        .modified()
        .ok()?
        .duration_since(UNIX_EPOCH)
        .ok()?
        .as_secs() as i64;
    Some((mtime, md.len() as i64))
}

fn parse_gain(s: Option<&str>) -> Option<f64> {
    s?.trim().trim_end_matches("dB").trim().parse().ok()
}

fn parse_file(
    path: &Path,
    mtime: i64,
    size: i64,
    claims: &CoverClaims,
    covers: &CoverCache,
) -> Option<Parsed> {
    let tagged = lofty::read_from_path(path).ok()?;
    let duration_ms = tagged.properties().duration().as_millis() as u64;
    let tag = tagged.primary_tag().or_else(|| tagged.first_tag());

    let stem = path
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();

    let (title, artist, album_artist, album, track_no, disc_no, year, tg, ag, picture) =
        match tag {
            Some(t) => {
                let artist = t.artist().map(|s| s.into_owned()).unwrap_or_default();
                let album_artist = t
                    .get_string(&ItemKey::AlbumArtist)
                    .map(str::to_owned)
                    .unwrap_or_else(|| artist.clone());
                let album_s = t.album().map(|s| s.into_owned()).unwrap_or_default();
                // Only the first track *that has art* claims its album; the rest skip
                // it, so at most one picture per album is ever decoded. Tracks without
                // embedded art fall back to folder art, checked once per directory.
                let picture = if !album_s.is_empty() && !claims.has(&album_s, &album_artist) {
                    let bytes = match t.pictures().first() {
                        Some(pic) if claims.claim(&album_s, &album_artist) => Some(pic.data().to_vec()),
                        Some(_) => None,
                        None => path
                            .parent()
                            .filter(|d| claims.first_visit(d))
                            .and_then(folder_cover)
                            .filter(|_| claims.claim(&album_s, &album_artist))
                            .and_then(|f| std::fs::read(f).ok()),
                    };
                    bytes.and_then(|b| covers.store(&b).ok())
                } else {
                    None
                };
                (
                    t.title().map(|s| s.into_owned()).unwrap_or(stem),
                    artist,
                    album_artist,
                    t.album().map(|s| s.into_owned()).filter(|s| !s.is_empty()),
                    t.track(),
                    t.disk(),
                    t.year(),
                    parse_gain(t.get_string(&ItemKey::ReplayGainTrackGain)),
                    parse_gain(t.get_string(&ItemKey::ReplayGainAlbumGain)),
                    picture,
                )
            }
            None => (stem, String::new(), String::new(), None, None, None, None, None, None, None),
        };

    Some(Parsed {
        path: path.to_string_lossy().into_owned(),
        mtime,
        size,
        title,
        artist,
        album_artist,
        album,
        track_no,
        disc_no,
        year,
        duration_ms,
        track_gain: tg,
        album_gain: ag,
        cover_hash: picture,
    })
}

/// Look for folder art next to the file (cover.jpg, folder.png, ...).
fn folder_cover(dir: &Path) -> Option<PathBuf> {
    const NAMES: &[&str] = &["cover", "folder", "front", "album"];
    let rd = std::fs::read_dir(dir).ok()?;
    for e in rd.flatten() {
        let p = e.path();
        let stem = p.file_stem()?.to_string_lossy().to_ascii_lowercase();
        let ext = p.extension().map(|e| e.to_string_lossy().to_ascii_lowercase());
        if NAMES.contains(&stem.as_str()) && matches!(ext.as_deref(), Some("jpg" | "jpeg" | "png")) {
            return Some(p);
        }
    }
    None
}

pub fn scan(
    db: &mut Db,
    covers: &CoverCache,
    roots: &[PathBuf],
    mut on_event: impl FnMut(ScanEvent),
) -> Result<ScanStats> {
    let t0 = Instant::now();
    let mut stats = ScanStats::default();
    let known = db.known_files()?;

    // 1. Walk (cheap: stat only).
    let mut found: Vec<(PathBuf, i64, i64)> = Vec::new();
    for root in roots {
        for e in WalkDir::new(root)
            .follow_links(true)
            .into_iter()
            .filter_entry(|e| e.depth() == 0 || !e.file_name().to_string_lossy().starts_with('.'))
            .flatten()
        {
            if e.file_type().is_file() && is_audio(e.path()) {
                if let Some((m, s)) = file_sig(e.path()) {
                    found.push((e.into_path(), m, s));
                }
            }
        }
    }
    stats.seen = found.len();
    on_event(ScanEvent::Discovered(found.len()));

    let seen_paths: HashSet<String> =
        found.iter().map(|(p, _, _)| p.to_string_lossy().into_owned()).collect();

    let to_parse: Vec<_> = found
        .into_iter()
        .filter(|(p, m, s)| known.get(p.to_string_lossy().as_ref()) != Some(&(*m, *s)))
        .collect();
    stats.unchanged = stats.seen - to_parse.len();

    // Albums that already have a thumbnail: no need to pull picture bytes again.
    let albums_with_cover: HashSet<(String, String)> = {
        let mut st = db.conn.prepare(
            "SELECT a.title, ar.name FROM albums a JOIN artists ar ON ar.id = a.artist_id WHERE a.cover_hash IS NOT NULL",
        )?;
        let rows = st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?;
        rows.flatten().collect()
    };

    // 2. Parse in parallel, write in batches from this thread.
    let total = to_parse.len();
    let (tx, rx) = crossbeam_channel::bounded::<Option<Parsed>>(64);
    let claims = CoverClaims::new(albums_with_cover);
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() as i64;

    std::thread::scope(|s| -> Result<()> {
        let claims = &claims;
        s.spawn(move || {
            to_parse.par_iter().for_each_with(tx, |tx, (p, m, sz)| {
                let parsed = parse_file(p, *m, *sz, claims, covers);
                let _ = tx.send(parsed);
            });
        });

        let txn = db.conn.transaction()?;
        let mut done = 0usize;
        for msg in rx {
            done += 1;
            let Some(p) = msg else {
                stats.failed += 1;
                continue;
            };
            stats.parsed += 1;

            let aa = if p.album_artist.is_empty() { "Artista desconhecido" } else { &p.album_artist };
            txn.execute("INSERT OR IGNORE INTO artists(name) VALUES (?1)", [aa])?;
            let artist_id: i64 =
                txn.query_row("SELECT id FROM artists WHERE name=?1", [aa], |r| r.get(0))?;

            let album_id: Option<i64> = match &p.album {
                Some(title) => {
                    txn.execute(
                        "INSERT OR IGNORE INTO albums(title, artist_id, year, added_at) VALUES (?1,?2,?3,?4)",
                        params![title, artist_id, p.year, now],
                    )?;
                    Some(txn.query_row(
                        "SELECT id FROM albums WHERE title=?1 AND artist_id=?2",
                        params![title, artist_id],
                        |r| r.get(0),
                    )?)
                }
                None => None,
            };

            if let (Some(aid), Some(hash)) = (album_id, &p.cover_hash) {
                txn.execute("UPDATE albums SET cover_hash=?1 WHERE id=?2", params![hash, aid])?;
                stats.covers_written += 1;
            }

            let old: Option<(i64, String, String, Option<String>)> = txn
                .query_row(
                    "SELECT t.id, t.title, t.artist, a.title FROM tracks t LEFT JOIN albums a ON a.id=t.album_id WHERE t.path=?1",
                    [&p.path],
                    |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
                )
                .ok();
            if let Some((oid, ot, oa, oal)) = &old {
                txn.execute(
                    "INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album) VALUES('delete', ?1, ?2, ?3, ?4)",
                    params![oid, ot, oa, oal.clone().unwrap_or_default()],
                )?;
            }

            txn.execute(
                "INSERT INTO tracks(path, mtime, size, title, artist, album_id, track_no, disc_no, year, duration_ms, track_gain, album_gain)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12)
                 ON CONFLICT(path) DO UPDATE SET mtime=excluded.mtime, size=excluded.size, title=excluded.title,
                   artist=excluded.artist, album_id=excluded.album_id, track_no=excluded.track_no,
                   disc_no=excluded.disc_no, year=excluded.year, duration_ms=excluded.duration_ms,
                   track_gain=excluded.track_gain, album_gain=excluded.album_gain",
                params![
                    p.path, p.mtime, p.size, p.title, p.artist, album_id, p.track_no, p.disc_no,
                    p.year, p.duration_ms as i64, p.track_gain, p.album_gain
                ],
            )?;
            let tid: i64 = txn.query_row("SELECT id FROM tracks WHERE path=?1", [&p.path], |r| r.get(0))?;
            txn.execute(
                "INSERT INTO tracks_fts(rowid, title, artist, album) VALUES (?1,?2,?3,?4)",
                params![tid, p.title, p.artist, p.album.clone().unwrap_or_default()],
            )?;

            if done % 250 == 0 {
                on_event(ScanEvent::Parsed { done, total });
            }
        }

        // 3. Remove tracks whose files are gone.
        let gone: Vec<(i64, String, String, String)> = {
            let mut st = txn.prepare(
                "SELECT t.id, t.path, t.title, t.artist, COALESCE(a.title,'') FROM tracks t LEFT JOIN albums a ON a.id=t.album_id",
            )?;
            let rows = st.query_map([], |r| {
                Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?, r.get(2)?, r.get(3)?, r.get(4)?))
            })?;
            rows.flatten()
                .filter(|(_, path, ..)| !seen_paths.contains(path))
                .map(|(id, _, t, a, al)| (id, t, a, al))
                .collect()
        };
        for (id, t, a, al) in &gone {
            txn.execute(
                "INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album) VALUES('delete', ?1, ?2, ?3, ?4)",
                params![id, t, a, al],
            )?;
            txn.execute("DELETE FROM tracks WHERE id=?1", [id])?;
        }
        stats.removed = gone.len();
        txn.execute("DELETE FROM albums WHERE id NOT IN (SELECT DISTINCT album_id FROM tracks WHERE album_id IS NOT NULL)", [])?;
        txn.commit()?;
        Ok(())
    })?;

    stats.elapsed_ms = t0.elapsed().as_millis();
    on_event(ScanEvent::Finished(stats.clone()));
    Ok(stats)
}
