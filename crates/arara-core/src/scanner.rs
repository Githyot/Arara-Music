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
    genre: Option<String>,
    composer: Option<String>,
    format: Option<String>,
    sample_rate: Option<u32>,
    bit_depth: Option<u8>,
    bitrate: Option<u32>,
    explicit: Option<bool>,
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
    let props = tagged.properties();
    let duration_ms = props.duration().as_millis() as u64;
    let format = Some(match tagged.file_type() {
        lofty::file::FileType::Flac => "FLAC",
        lofty::file::FileType::Mpeg => "MP3",
        lofty::file::FileType::Opus => "Opus",
        lofty::file::FileType::Vorbis => "Vorbis",
        lofty::file::FileType::Mp4 => {
            // ALAC and AAC share the container; ALAC reports a bit depth.
            if props.bit_depth().is_some() { "ALAC" } else { "AAC" }
        }
        lofty::file::FileType::Wav => "WAV",
        lofty::file::FileType::Aiff => "AIFF",
        lofty::file::FileType::WavPack => "WavPack",
        lofty::file::FileType::Ape => "APE",
        lofty::file::FileType::Aac => "AAC",
        _ => "",
    })
    .filter(|f| !f.is_empty())
    .map(str::to_owned);
    let (sample_rate, bit_depth, bitrate) = (props.sample_rate(), props.bit_depth(), props.audio_bitrate());
    let tag = tagged.primary_tag().or_else(|| tagged.first_tag());

    let stem = path
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();

    // Parental advisory: iTunes rtng / ITUNESADVISORY (lofty maps both to
    // ParentalAdvisory; Vorbis comments keep ITUNESADVISORY as an unknown key),
    // or a plain EXPLICIT / CONTENTRATING field.
    let explicit = tag.and_then(|t| {
        t.get_string(&ItemKey::ParentalAdvisory)
            .and_then(crate::explicit::from_tag_value)
            .or_else(|| {
                ["ITUNESADVISORY", "EXPLICIT", "CONTENTRATING", "CONTENT RATING", "ADVISORY"].iter().find_map(|k| {
                    t.get_string(&ItemKey::Unknown((*k).to_string())).and_then(crate::explicit::from_tag_value)
                })
            })
    });

    let (title, artist, album_artist, album, track_no, disc_no, year, tg, ag, picture, genre, composer) =
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
                let picture = if album_s.is_empty() {
                    // No album to share art with: the track keeps its own picture.
                    t.pictures().first().and_then(|pic| covers.store(pic.data()).ok())
                } else if !claims.has(&album_s, &album_artist) {
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
                    t.genre().map(|s| s.trim().to_owned()).filter(|s| !s.is_empty()),
                    t.get_string(&ItemKey::Composer).map(|s| s.trim().to_owned()).filter(|s| !s.is_empty()),
                )
            }
            None => (stem, String::new(), String::new(), None, None, None, None, None, None, None, None, None),
        };

    // Store titles like "Song (Explicit)" or "Song [Explicit Version]".
    let explicit = explicit.or_else(|| {
        let l = title.to_lowercase();
        (l.contains("(explicit") || l.contains("[explicit") || l.contains("(explícit")).then_some(true)
    });

    Some(Parsed {
        explicit,
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
        genre,
        composer,
        format,
        sample_rate,
        bit_depth,
        bitrate,
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
    let _writer = crate::db::WRITER.lock().unwrap_or_else(|e| e.into_inner());
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

        // Commit in small batches so the write lock is released often: the UI
        // (saving the queue, play counts, stars) never waits more than a moment.
        let mut txn = db.conn.unchecked_transaction()?;
        let mut batch_start = Instant::now();
        let mut done = 0usize;
        for msg in rx {
            done += 1;
            let Some(p) = msg else {
                stats.failed += 1;
                continue;
            };
            stats.parsed += 1;

            let cover_written = crate::db::upsert_track(
                &txn,
                &crate::db::NewTrack {
                    path: &p.path,
                    mtime: p.mtime,
                    size: p.size,
                    title: &p.title,
                    artist: &p.artist,
                    album_artist: &p.album_artist,
                    album: p.album.as_deref(),
                    track_no: p.track_no,
                    disc_no: p.disc_no,
                    year: p.year,
                    duration_ms: p.duration_ms as i64,
                    track_gain: p.track_gain,
                    album_gain: p.album_gain,
                    cover_hash: p.cover_hash.as_deref(),
                    genre: p.genre.as_deref(),
                    composer: p.composer.as_deref(),
                    format: p.format.as_deref(),
                    sample_rate: p.sample_rate,
                    bit_depth: p.bit_depth,
                    bitrate: p.bitrate,
                    explicit: p.explicit,
                },
                now,
            )?;
            if cover_written {
                stats.covers_written += 1;
            }

            if done % 250 == 0 {
                on_event(ScanEvent::Parsed { done, total });
            }
            if done % 200 == 0 || batch_start.elapsed().as_millis() > 400 {
                txn.commit()?;
                txn = db.conn.unchecked_transaction()?;
                batch_start = Instant::now();
            }
        }

        // 3. Remove local tracks whose files are gone (remote tracks belong to their server's sync).
        stats.removed = crate::db::delete_tracks_where(&txn, |path| {
            !path.starts_with(crate::remote::PREFIX) && !seen_paths.contains(path)
        })?;
        txn.commit()?;
        Ok(())
    })?;

    stats.elapsed_ms = t0.elapsed().as_millis();
    on_event(ScanEvent::Finished(stats.clone()));
    Ok(stats)
}
