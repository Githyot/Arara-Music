//! Artist and album info saved next to the music.
//!
//! What MusicBrainz and Wikipedia say about an album is written to a small
//! hidden file in the album folder (`.arara-album.json`); the artist's goes to
//! `.arara-artist.json` (and the photo to `.arara-artist.jpg`) in the artist
//! folder, or in each of their album folders when the library isn't laid out
//! as `Artist/Album/`. The `kv` table keeps a copy, so pages open instantly;
//! the files mean nothing is lost when the database is (and other computers
//! with the same disk get the info for free), like `.lrc` lyrics files.
//!
//! Everything here runs on worker threads: a locked or sleeping external disk
//! can make any file access block for a long time.

use serde_json::{json, Value};
use std::path::{Path, PathBuf};

use crate::db::Db;
use crate::info::{self, AlbumHint};
use crate::remote;

pub const ALBUM_FILE: &str = ".arara-album.json";
pub const ARTIST_FILE: &str = ".arara-artist.json";
pub const ARTIST_PHOTO: &str = ".arara-artist.jpg";
/// Bump when the matching changes enough that saved answers should be redone.
const FORMAT: i64 = 1;

fn norm(s: &str) -> String {
    crate::import::norm(s)
}

/// Where the files go and what may be touched.
#[derive(Debug, Clone, Default)]
pub struct Options {
    /// Write info files next to the music (otherwise only the app cache).
    pub save_files: bool,
    /// Music folders (never used as an artist folder).
    pub roots: Vec<String>,
    /// Folders that can't be read now (locked/unplugged disk): left alone.
    pub skip: Vec<String>,
    /// App cache for downloaded photos (`covers/web`).
    pub photo_cache: PathBuf,
    /// Go online for what's missing.
    pub online: bool,
}

impl Options {
    fn usable(&self, dir: &Path) -> bool {
        !self.skip.iter().any(|s| dir.starts_with(s))
    }
}

fn under(prefix: &Path) -> String {
    let mut p = prefix.to_string_lossy().into_owned();
    if !p.ends_with(std::path::MAIN_SEPARATOR) {
        p.push(std::path::MAIN_SEPARATOR);
    }
    p
}

/// "CD1", "Disc 2", "Disco 3": a disc folder inside the album folder.
fn is_disc_folder(name: &str) -> bool {
    let l = name.to_lowercase();
    ["cd", "disc", "disco", "disk", "disque"].iter().filter_map(|p| l.strip_prefix(p)).any(|r| {
        let r = r.trim_start_matches([' ', '_', '-', '.']);
        !r.is_empty() && r.chars().all(|c| c.is_ascii_digit())
    })
}

fn local_paths(db: &Db, sql: &str, id: i64) -> Vec<String> {
    let Ok(mut st) = db.conn.prepare(sql) else { return vec![] };
    st.query_map([id], |r| r.get::<_, String>(0))
        .map(|r| r.flatten().filter(|p| !remote::is_remote(p)).collect())
        .unwrap_or_default()
}

/// The folder that holds this album and nothing else, from the index alone.
pub fn album_dir(db: &Db, album_id: i64) -> Option<PathBuf> {
    let paths = local_paths(db, "SELECT path FROM tracks WHERE album_id = ?1", album_id);
    let mut dir: Option<PathBuf> = None;
    for p in &paths {
        let mut d = Path::new(p).parent()?.to_path_buf();
        if d.file_name().and_then(|n| n.to_str()).is_some_and(is_disc_folder) {
            d = d.parent()?.to_path_buf();
        }
        match &dir {
            None => dir = Some(d),
            Some(x) if *x == d => {}
            Some(_) => return None, // spread over several folders
        }
    }
    let dir = dir?;
    // A folder of loose songs from many albums isn't this album's folder.
    let other: bool = db
        .conn
        .query_row(
            "SELECT 1 FROM tracks WHERE substr(path, 1, length(?1)) = ?1 AND album_id IS NOT ?2 LIMIT 1",
            rusqlite::params![under(&dir), album_id],
            |_| Ok(()),
        )
        .is_ok();
    (!other).then_some(dir)
}

/// Albums credited to this artist that have local files, most played first.
fn artist_albums(db: &Db, artist_id: i64) -> Vec<i64> {
    let Ok(mut st) = db.conn.prepare(
        "SELECT a.id FROM albums a JOIN tracks t ON t.album_id = a.id
         WHERE a.artist_id = ?1 AND t.path NOT LIKE 'remote://%'
         GROUP BY a.id ORDER BY SUM(t.play_count) DESC, a.id",
    ) else {
        return vec![];
    };
    st.query_map([artist_id], |r| r.get(0)).map(|r| r.flatten().collect()).unwrap_or_default()
}

/// Where an artist's file goes: their own folder (`Artist/Album/` layouts),
/// otherwise each of their album folders.
pub fn artist_dirs(db: &Db, artist_id: i64, name: &str, roots: &[String]) -> Vec<PathBuf> {
    let albums: Vec<PathBuf> = artist_albums(db, artist_id).into_iter().filter_map(|a| album_dir(db, a)).collect();
    let Some(first) = albums.first() else { return vec![] };
    if let Some(parent) = first.parent() {
        let is_root = roots.iter().any(|r| Path::new(r) == parent) || parent.parent().is_none();
        if !is_root && albums.iter().all(|d| d.parent() == Some(parent)) {
            let named = parent.file_name().and_then(|n| n.to_str()).is_some_and(|n| norm(n) == norm(name));
            // or: every song under it is this artist's
            let only_theirs = || {
                db.conn
                    .query_row(
                        "SELECT 1 FROM tracks t LEFT JOIN albums a ON a.id = t.album_id
                         WHERE substr(t.path, 1, length(?1)) = ?1 AND a.artist_id IS NOT ?2 LIMIT 1",
                        rusqlite::params![under(parent), artist_id],
                        |_| Ok(()),
                    )
                    .is_err()
            };
            if named || only_theirs() {
                return vec![parent.to_path_buf()];
            }
        }
    }
    albums
}

/// A saved answer, if the file is there and is about the same album/artist.
pub fn read_file(dir: &Path, file: &str, kind: &str, key: &str) -> Option<(i64, Value)> {
    let text = std::fs::read_to_string(dir.join(file)).ok()?;
    let v: Value = serde_json::from_str(&text).ok()?;
    if v["kind"] != kind || v["format"].as_i64() != Some(FORMAT) || norm(v["key"].as_str().unwrap_or("")) != norm(key) {
        return None;
    }
    let data = v["data"].clone();
    (!data.is_null()).then(|| (v["savedAt"].as_i64().unwrap_or(0), data))
}

/// Save an answer next to the music. Writes only when something changed, via
/// a temporary file, so a half-written file never replaces a good one.
pub fn write_file(dir: &Path, file: &str, kind: &str, key: &str, at: i64, data: &Value) -> std::io::Result<bool> {
    let mut clean = data.clone();
    if let Some(o) = clean.as_object_mut() {
        // local paths are per computer
        o.remove("photo");
        o.remove("saved");
    }
    if let Some((_, old)) = read_file(dir, file, kind, key) {
        if old == clean {
            return Ok(false);
        }
    }
    let body = json!({
        "format": FORMAT,
        "kind": kind,
        "key": key,
        "savedAt": at,
        "app": "Arara Music",
        "about": "Informações do MusicBrainz e da Wikipédia salvas pelo Arara Music. Pode apagar: o app busca de novo.",
        "data": clean,
    });
    let tmp = dir.join(format!("{file}.tmp"));
    std::fs::write(&tmp, serde_json::to_string_pretty(&body).unwrap_or_default())?;
    std::fs::rename(&tmp, dir.join(file)).inspect_err(|_| {
        let _ = std::fs::remove_file(&tmp);
    })?;
    Ok(true)
}

/// Names used as cache key: (artist, title) of an album.
pub fn album_names(db: &Db, album_id: i64) -> Option<(String, String)> {
    db.conn
        .query_row(
            "SELECT COALESCE(ar.name, ''), al.title FROM albums al LEFT JOIN artists ar ON ar.id = al.artist_id WHERE al.id = ?1",
            [album_id],
            |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)),
        )
        .ok()
}

pub fn album_key(artist: &str, title: &str) -> String {
    format!("{artist}\u{1f}{title}")
}

fn artist_name(db: &Db, artist_id: i64) -> Option<String> {
    db.conn.query_row("SELECT name FROM artists WHERE id = ?1", [artist_id], |r| r.get(0)).ok()
}

/// What happened while resolving, for the background counter.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
    /// Already cached and saved.
    Cached,
    /// Read back from a file next to the music.
    FromFile,
    /// Looked up online now.
    Fetched,
    /// Nothing known (or no network / online lookups off).
    Missing,
    /// The network failed during the lookup.
    Offline,
}

struct Plan<'a> {
    kind: &'a str,
    key: String,
    file: &'a str,
    dirs: Vec<PathBuf>,
}

/// Cache → saved file → online, delivering the answer as soon as it is known
/// (`deliver` runs before any slow file writes), then making sure it is saved.
fn resolve(db: &Db, plan: Plan, now: i64, force: bool, opts: &Options, fetch: impl FnOnce() -> Option<Value>, deliver: &mut dyn FnMut(&Value)) -> (Value, Outcome) {
    let dirs: Vec<&PathBuf> = plan.dirs.iter().filter(|d| opts.usable(d)).collect();
    let (data, outcome) = match (!force).then(|| info::cached(db, plan.kind, &plan.key, now)).flatten() {
        Some(v) => (v, Outcome::Cached),
        None => {
            let saved = if force { None } else { dirs.iter().find_map(|d| read_file(d, plan.file, plan.kind, &plan.key)) };
            match saved {
                Some((at, mut v)) => {
                    v["saved"] = json!(true);
                    info::remember(db, plan.kind, &plan.key, at.min(now), &v);
                    (v, Outcome::FromFile)
                }
                None if opts.online => {
                    let errs = info::net_errors();
                    let v = info::cached_or_fetch(db, plan.kind, &plan.key, now, true, fetch);
                    let o = if !v.is_null() {
                        Outcome::Fetched
                    } else if info::net_errors() != errs {
                        Outcome::Offline
                    } else {
                        Outcome::Missing
                    };
                    (v, o)
                }
                None => {
                    let v = info::stale(db, plan.kind, &plan.key);
                    let o = if v.is_null() { Outcome::Missing } else { Outcome::Cached };
                    (v, o)
                }
            }
        }
    };
    let mut data = data;
    deliver(&data);
    if !data.is_null() && opts.save_files && outcome != Outcome::FromFile {
        let mut wrote_any = false;
        for d in &dirs {
            match write_file(d, plan.file, plan.kind, &plan.key, now, &data) {
                Ok(_) => wrote_any = true,
                Err(e) => log::debug!("info file not saved in {}: {e}", d.display()),
            }
        }
        if wrote_any {
            data["saved"] = json!(true);
            info::remember(db, plan.kind, &plan.key, now, &data);
        }
    }
    let outcome = if outcome == Outcome::Cached && data.is_null() { Outcome::Missing } else { outcome };
    (data, outcome)
}

/// Album info (see module docs). `deliver` gets the answer first; the return
/// value also says where it came from.
pub fn album(db: &Db, album_id: i64, now: i64, force: bool, opts: &Options, deliver: &mut dyn FnMut(&Value)) -> (Value, Outcome) {
    let Some((artist, title)) = album_names(db, album_id) else {
        deliver(&Value::Null);
        return (Value::Null, Outcome::Missing);
    };
    let dir = album_dir(db, album_id);
    let plan = Plan { kind: "album", key: album_key(&artist, &title), file: ALBUM_FILE, dirs: dir.iter().cloned().collect() };
    let usable_dir = dir.as_ref().is_some_and(|d| opts.usable(d));
    let fetch = || {
        // The edition hints come from the files: only read them when the disk is usable.
        let paths = local_paths(db, "SELECT path FROM tracks WHERE album_id = ?1 ORDER BY disc_no, track_no", album_id);
        let mut titles: Vec<String> = vec![];
        if let Ok(mut st) = db.conn.prepare("SELECT title FROM tracks WHERE album_id = ?1") {
            if let Ok(rows) = st.query_map([album_id], |r| r.get::<_, String>(0)) {
                for t in rows.flatten() {
                    let n = norm(&t);
                    if !titles.contains(&n) {
                        titles.push(n);
                    }
                }
            }
        }
        let mut hint = AlbumHint { tracks: titles.len(), ..Default::default() };
        let mut mbid = None;
        if usable_dir || dir.is_none() {
            if let Some(p) = paths.iter().find(|p| opts.usable(Path::new(p))) {
                let f = info::file_details(p);
                mbid = f["mbid"]["release"].as_str().map(str::to_owned);
                hint.barcode = f["fields"]["barcode"].as_str().map(str::to_owned);
                hint.catalog = f["fields"]["catalog"].as_str().map(str::to_owned);
            }
        }
        info::fetch_album(&title, &artist, mbid.as_deref(), &hint)
    };
    resolve(db, plan, now, force, opts, fetch, deliver)
}

/// Artist info, with the photo downloaded once and kept next to the music too.
pub fn artist(db: &Db, artist_id: i64, now: i64, force: bool, opts: &Options, deliver: &mut dyn FnMut(&Value)) -> (Value, Outcome) {
    let Some(name) = artist_name(db, artist_id) else {
        deliver(&Value::Null);
        return (Value::Null, Outcome::Missing);
    };
    let dirs = artist_dirs(db, artist_id, &name, &opts.roots);
    let plan = Plan { kind: "artist", key: name.clone(), file: ARTIST_FILE, dirs: dirs.clone() };
    let fetch = || {
        // Picard writes the artist MBID into each song: use one of theirs.
        let paths = local_paths(db, "SELECT t.path FROM tracks t JOIN albums a ON a.id = t.album_id WHERE a.artist_id = ?1 LIMIT 3", artist_id);
        let mbid = paths
            .iter()
            .filter(|p| opts.usable(Path::new(p)))
            .find_map(|p| info::file_details(p)["mbid"]["artist"].as_str().map(str::to_owned));
        info::fetch_artist(&name, mbid.as_deref())
    };
    let usable: Vec<PathBuf> = dirs.iter().filter(|d| opts.usable(d)).cloned().collect();
    let photo_cache = opts.photo_cache.clone();
    let save = opts.save_files;
    // The photo is part of the answer: add it before the page sees it.
    let mut with_photo = |v: &Value| {
        let mut v = v.clone();
        if let Some(p) = photo_for(&v, &usable, &photo_cache, save) {
            v["photo"] = json!(remote::file_url(&p));
        }
        deliver(&v);
    };
    let (mut data, outcome) = resolve(db, plan, now, force, opts, fetch, &mut with_photo);
    if let Some(p) = photo_for(&data, &usable, &opts.photo_cache, false) {
        data["photo"] = json!(remote::file_url(&p));
    }
    (data, outcome)
}

/// Local file for the artist photo: the app cache, else the copy saved next
/// to the music, else download it. With `save`, copies it next to the music.
fn photo_for(data: &Value, dirs: &[PathBuf], cache: &Path, save: bool) -> Option<String> {
    let url = data["wiki"]["image"].as_str()?;
    let saved = dirs.iter().map(|d| d.join(ARTIST_PHOTO)).find(|p| p.is_file());
    let cached = info::cache_image_cached(url, cache).or_else(|| saved.as_ref().map(|p| p.to_string_lossy().into_owned())).or_else(|| info::cache_image(url, cache))?;
    if save && saved.is_none() {
        if let Some(d) = dirs.first() {
            let tmp = d.join(format!("{ARTIST_PHOTO}.tmp"));
            if std::fs::copy(&cached, &tmp).is_ok() {
                let _ = std::fs::rename(&tmp, d.join(ARTIST_PHOTO));
            }
            let _ = std::fs::remove_file(&tmp);
        }
    }
    Some(cached)
}

/// Everything worth looking up, most played first: each album with local
/// files, followed by its artist the first time they show up.
pub fn prefetch_list(db: &Db) -> Vec<(&'static str, i64)> {
    let mut out = vec![];
    let Ok(mut st) = db.conn.prepare(
        "SELECT a.id, a.artist_id FROM albums a JOIN tracks t ON t.album_id = a.id
         WHERE t.path NOT LIKE 'remote://%'
         GROUP BY a.id ORDER BY SUM(t.play_count) DESC, MAX(t.last_played) DESC, a.id",
    ) else {
        return out;
    };
    let rows: Vec<(i64, Option<i64>)> = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).map(|r| r.flatten().collect()).unwrap_or_default();
    let mut seen = std::collections::HashSet::new();
    for (album, artist) in rows {
        out.push(("album", album));
        if let Some(a) = artist {
            if seen.insert(a) {
                out.push(("artist", a));
            }
        }
    }
    out
}

/// Cheap check (index + cache only): does this item still need work?
/// Items already cached are still visited once per run, to make sure their
/// file exists, but that needs no network.
pub fn is_cached(db: &Db, kind: &str, id: i64, now: i64) -> bool {
    let key = match kind {
        "album" => album_names(db, id).map(|(a, t)| album_key(&a, &t)),
        _ => artist_name(db, id),
    };
    key.is_some_and(|k| info::cached(db, kind, &k, now).is_some())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disc_folders() {
        assert!(is_disc_folder("CD1"));
        assert!(is_disc_folder("Disc 2"));
        assert!(is_disc_folder("disco_3"));
        assert!(!is_disc_folder("Discovery"));
        assert!(!is_disc_folder("CD"));
    }

    #[test]
    fn file_round_trip_checks_the_key() {
        let dir = tempfile::tempdir().unwrap();
        let data = json!({ "title": "Álbum", "photo": "file:///x.jpg" });
        assert!(write_file(dir.path(), ALBUM_FILE, "album", "A\u{1f}Álbum", 10, &data).unwrap());
        // unchanged → not rewritten
        assert!(!write_file(dir.path(), ALBUM_FILE, "album", "A\u{1f}Álbum", 20, &data).unwrap());
        let (at, back) = read_file(dir.path(), ALBUM_FILE, "album", "a\u{1f}album").unwrap();
        assert_eq!(at, 10);
        assert_eq!(back["title"], "Álbum");
        assert!(back.get("photo").is_none(), "local paths are not saved");
        assert!(read_file(dir.path(), ALBUM_FILE, "album", "B\u{1f}Outro").is_none());
        assert!(read_file(dir.path(), ALBUM_FILE, "artist", "A\u{1f}Álbum").is_none());
    }
}
