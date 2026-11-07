//! Persistent library index (SQLite, WAL).
//!
//! The database *is* the cache: on startup the UI reads albums/tracks straight
//! from here (milliseconds), and the scanner only touches files whose
//! mtime/size changed since the last run.

use rusqlite::{params, Connection, OptionalExtension};
use std::path::Path;

use crate::Result;

pub const SCHEMA_VERSION: i64 = 1;

const SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS artists (
    id    INTEGER PRIMARY KEY,
    name  TEXT NOT NULL UNIQUE COLLATE NOCASE
);
CREATE TABLE IF NOT EXISTS albums (
    id         INTEGER PRIMARY KEY,
    title      TEXT NOT NULL COLLATE NOCASE,
    artist_id  INTEGER REFERENCES artists(id),
    year       INTEGER,
    cover_hash TEXT,              -- blake3 of the source image; thumbnail lives on disk
    added_at   INTEGER NOT NULL,
    UNIQUE(title, artist_id)
);
CREATE TABLE IF NOT EXISTS tracks (
    id          INTEGER PRIMARY KEY,
    path        TEXT NOT NULL UNIQUE,
    mtime       INTEGER NOT NULL,
    size        INTEGER NOT NULL,
    title       TEXT NOT NULL,
    artist      TEXT NOT NULL,
    album_id    INTEGER REFERENCES albums(id),
    track_no    INTEGER,
    disc_no     INTEGER,
    year        INTEGER,
    duration_ms INTEGER NOT NULL DEFAULT 0,
    track_gain  REAL,
    album_gain  REAL,
    starred     INTEGER NOT NULL DEFAULT 0,
    play_count  INTEGER NOT NULL DEFAULT 0,
    last_played INTEGER,
    cover_hash  TEXT,              -- own art, for tracks without an album tag
    genre       TEXT,
    composer    TEXT,
    added_at    INTEGER,
    format      TEXT,              -- FLAC, MP3, Opus…
    sample_rate INTEGER,
    bit_depth   INTEGER,
    bitrate     INTEGER,            -- kbit/s
    explicit        INTEGER,        -- advisory from the tag/server: 1 explicit, 0 clean, NULL unknown
    explicit_lyrics INTEGER,        -- guess from the lyrics (see explicit.rs)
    explicit_user   INTEGER         -- the user's choice, overrides both
);
CREATE INDEX IF NOT EXISTS tracks_album ON tracks(album_id, disc_no, track_no);

-- Full-text search over the library (title/artist/album), kept in sync by triggers.
CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts USING fts5(
    title, artist, album, content='', tokenize='unicode61 remove_diacritics 2'
);

CREATE TABLE IF NOT EXISTS lyrics (
    track_id   INTEGER PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
    source     TEXT NOT NULL,      -- 'sidecar' | 'embedded' | 'lrclib' | 'user' | 'none'
    synced     TEXT,               -- LRC (possibly enhanced, with <mm:ss.xx> word stamps)
    plain      TEXT,
    fetched_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS playlists (
    id    INTEGER PRIMARY KEY,
    name  TEXT NOT NULL,
    query TEXT,                   -- smart playlist: a saved search (see query.rs)
    sort  TEXT,
    lim   INTEGER
);
CREATE TABLE IF NOT EXISTS playlist_items (
    playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    pos         INTEGER NOT NULL,
    track_id    INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    PRIMARY KEY (playlist_id, pos)
);
CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT);

-- Transition analysis (silence, fade ramps, loudness, tempo), see analysis.rs.
CREATE TABLE IF NOT EXISTS track_analysis (
    track_id INTEGER PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
    version  INTEGER NOT NULL,
    mtime    INTEGER NOT NULL,
    json     TEXT NOT NULL
);

-- Remote libraries (Subsonic/Navidrome, Jellyfin). Their tracks live in `tracks`
-- like local ones, with path 'remote://<server id>/<item id>', so search, stars,
-- playlists, lyrics and the queue work the same and the catalog is cached offline.
CREATE TABLE IF NOT EXISTS servers (
    id          INTEGER PRIMARY KEY,
    kind        TEXT NOT NULL,     -- 'subsonic' | 'jellyfin'
    name        TEXT NOT NULL,
    url         TEXT NOT NULL,
    username    TEXT NOT NULL,
    auth        TEXT NOT NULL,     -- JSON: derived token, never the password
    last_sync   INTEGER,
    track_count INTEGER NOT NULL DEFAULT 0,
    last_error  TEXT
);
"#;

/// Serializes writers (local scan, remote syncs) so long transactions never
/// collide on SQLite's single write lock.
pub static WRITER: std::sync::Mutex<()> = std::sync::Mutex::new(());

/// One track to insert or update, from a file tag or a remote server.
pub struct NewTrack<'a> {
    pub path: &'a str,
    pub mtime: i64,
    pub size: i64,
    pub title: &'a str,
    pub artist: &'a str,
    pub album_artist: &'a str,
    pub album: Option<&'a str>,
    pub track_no: Option<u32>,
    pub disc_no: Option<u32>,
    pub year: Option<u32>,
    pub duration_ms: i64,
    pub track_gain: Option<f64>,
    pub album_gain: Option<f64>,
    pub cover_hash: Option<&'a str>,
    pub genre: Option<&'a str>,
    pub composer: Option<&'a str>,
    pub format: Option<&'a str>,
    pub sample_rate: Option<u32>,
    pub bit_depth: Option<u8>,
    pub bitrate: Option<u32>,
    /// Parental advisory from the tag or server (None = unknown).
    pub explicit: Option<bool>,
}

/// Insert/update one track (plus its artist, album and search entry) on an open
/// transaction. Returns true when a cover hash was written to its album.
pub fn upsert_track(c: &Connection, p: &NewTrack, now: i64) -> Result<bool> {
    let aa = if p.album_artist.is_empty() { "Artista desconhecido" } else { p.album_artist };
    c.execute("INSERT OR IGNORE INTO artists(name) VALUES (?1)", [aa])?;
    let artist_id: i64 = c.query_row("SELECT id FROM artists WHERE name=?1", [aa], |r| r.get(0))?;

    let album_id: Option<i64> = match p.album {
        Some(title) => {
            c.execute(
                "INSERT OR IGNORE INTO albums(title, artist_id, year, added_at) VALUES (?1,?2,?3,?4)",
                params![title, artist_id, p.year, now],
            )?;
            Some(c.query_row(
                "SELECT id FROM albums WHERE title=?1 AND artist_id=?2",
                params![title, artist_id],
                |r| r.get(0),
            )?)
        }
        None => None,
    };
    let mut cover_written = false;
    if let (Some(aid), Some(hash)) = (album_id, p.cover_hash) {
        c.execute("UPDATE albums SET cover_hash=?1 WHERE id=?2", params![hash, aid])?;
        cover_written = true;
    }
    // A track without an album keeps its own picture (e.g. downloaded singles).
    let track_cover = if album_id.is_none() { p.cover_hash } else { None };
    if track_cover.is_some() {
        cover_written = true;
    }

    let old: Option<(i64, String, String, Option<String>)> = c
        .query_row(
            "SELECT t.id, t.title, t.artist, a.title FROM tracks t LEFT JOIN albums a ON a.id=t.album_id WHERE t.path=?1",
            [p.path],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
        )
        .optional()?;
    if let Some((oid, ot, oa, oal)) = &old {
        c.execute(
            "INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album) VALUES('delete', ?1, ?2, ?3, ?4)",
            params![oid, ot, oa, oal.clone().unwrap_or_default()],
        )?;
    }
    c.execute(
        "INSERT INTO tracks(path, mtime, size, title, artist, album_id, track_no, disc_no, year, duration_ms,
                            track_gain, album_gain, cover_hash, genre, composer, added_at,
                            format, sample_rate, bit_depth, bitrate, explicit)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20,?21)
         ON CONFLICT(path) DO UPDATE SET mtime=excluded.mtime, size=excluded.size, title=excluded.title,
           artist=excluded.artist, album_id=excluded.album_id, track_no=excluded.track_no,
           disc_no=excluded.disc_no, year=excluded.year, duration_ms=excluded.duration_ms,
           track_gain=excluded.track_gain, album_gain=excluded.album_gain,
           cover_hash=COALESCE(excluded.cover_hash, CASE WHEN excluded.album_id IS NULL THEN tracks.cover_hash END),
           genre=excluded.genre, composer=excluded.composer,
           added_at=COALESCE(tracks.added_at, excluded.added_at),
           format=excluded.format, sample_rate=excluded.sample_rate, bit_depth=excluded.bit_depth, bitrate=excluded.bitrate,
           explicit=excluded.explicit",
        params![
            p.path, p.mtime, p.size, p.title, p.artist, album_id, p.track_no, p.disc_no,
            p.year, p.duration_ms, p.track_gain, p.album_gain, track_cover, p.genre, p.composer,
            if p.mtime > 0 && !p.path.starts_with(crate::remote::PREFIX) { p.mtime } else { now },
            p.format, p.sample_rate, p.bit_depth, p.bitrate, p.explicit
        ],
    )?;
    let tid: i64 = c.query_row("SELECT id FROM tracks WHERE path=?1", [p.path], |r| r.get(0))?;
    c.execute(
        "INSERT INTO tracks_fts(rowid, title, artist, album) VALUES (?1,?2,?3,?4)",
        params![tid, p.title, p.artist, p.album.unwrap_or_default()],
    )?;
    Ok(cover_written)
}

/// Delete tracks (and their search entries) whose path matches `filter`, then
/// drop albums left empty. Returns how many tracks were removed.
pub fn delete_tracks_where(c: &Connection, filter: impl Fn(&str) -> bool) -> Result<usize> {
    let gone: Vec<(i64, String, String, String)> = {
        let mut st = c.prepare(
            "SELECT t.id, t.path, t.title, t.artist, COALESCE(a.title,'') FROM tracks t LEFT JOIN albums a ON a.id=t.album_id",
        )?;
        let rows = st.query_map([], |r| {
            Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?, r.get(2)?, r.get(3)?, r.get(4)?))
        })?;
        rows.flatten()
            .filter(|(_, path, ..)| filter(path))
            .map(|(id, _, t, a, al)| (id, t, a, al))
            .collect()
    };
    for (id, t, a, al) in &gone {
        c.execute(
            "INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album) VALUES('delete', ?1, ?2, ?3, ?4)",
            params![id, t, a, al],
        )?;
        c.execute("DELETE FROM tracks WHERE id=?1", [id])?;
    }
    c.execute("DELETE FROM albums WHERE id NOT IN (SELECT DISTINCT album_id FROM tracks WHERE album_id IS NOT NULL)", [])?;
    Ok(gone.len())
}

pub struct Db {
    pub conn: Connection,
}

#[derive(Debug, Clone)]
pub struct TrackRow {
    pub id: i64,
    pub path: String,
    pub title: String,
    pub artist: String,
    pub album: Option<String>,
    pub album_id: Option<i64>,
    pub duration_ms: i64,
    pub starred: bool,
    pub cover_hash: Option<String>,
    /// ReplayGain in dB, when the file is tagged.
    pub track_gain: Option<f64>,
    pub album_gain: Option<f64>,
    pub year: Option<i64>,
    pub genre: Option<String>,
    pub album_artist: Option<String>,
    pub format: Option<String>,
    pub sample_rate: Option<i64>,
    pub bit_depth: Option<i64>,
    pub bitrate: Option<i64>,
    /// 0 = not explicit, 1 = explicit (tag, server or user), 2 = only the
    /// lyrics look explicit (shown when the preference allows).
    pub explicit: i64,
}

impl TrackRow {
    /// Quality badge like Euphonica's: "Hi-Res", "Sem perdas" or "" (lossy),
    /// plus a detail line ("FLAC · 24 bits · 96 kHz", "MP3 · 320 kbps").
    pub fn quality(&self) -> (&'static str, String) {
        let f = self.format.clone().unwrap_or_default();
        let lossless = matches!(f.as_str(), "FLAC" | "ALAC" | "WAV" | "AIFF" | "WavPack" | "APE");
        let rate = self.sample_rate.unwrap_or(0);
        let bits = self.bit_depth.unwrap_or(0);
        let grade = if lossless && (bits > 16 || rate > 48_000) { "Hi-Res" } else if lossless { "Sem perdas" } else { "" };
        let mut parts = vec![];
        if !f.is_empty() {
            parts.push(f);
        }
        if lossless && bits > 0 {
            parts.push(format!("{bits} bits"));
        }
        if rate > 0 {
            let k = rate as f64 / 1000.0;
            parts.push(if k.fract() == 0.0 { format!("{k:.0} kHz") } else { format!("{k:.1} kHz").replace('.', ",") });
        }
        if !lossless {
            if let Some(b) = self.bitrate.filter(|b| *b > 0) {
                parts.push(format!("{b} kbps"));
            }
        }
        (grade, parts.join(" · "))
    }
}

#[derive(Debug, Clone)]
pub struct ArtistRow {
    pub id: i64,
    pub name: String,
    pub album_count: i64,
    pub cover_hash: Option<String>,
}

#[derive(Debug, Clone)]
pub struct PlaylistRow {
    pub id: i64,
    pub name: String,
    pub track_count: i64,
    pub cover_hash: Option<String>,
    /// (query, sort, limit) for smart playlists.
    pub smart: Option<(String, String, i64)>,
}

pub(crate) const TRACK_COLS: &str =
    "t.id, t.path, t.title, t.artist, a.title, t.album_id, t.duration_ms, t.starred, COALESCE(a.cover_hash, t.cover_hash),
     t.track_gain, t.album_gain, COALESCE(t.year, a.year), t.genre,
     (SELECT name FROM artists WHERE id = a.artist_id), t.format, t.sample_rate, t.bit_depth, t.bitrate,
     CASE WHEN COALESCE(t.explicit_user, t.explicit) = 1 THEN 1
          WHEN COALESCE(t.explicit_user, t.explicit) = 0 THEN 0
          WHEN t.explicit_lyrics = 1 THEN 2 ELSE 0 END";

#[derive(Debug, Clone)]
pub struct AlbumRow {
    pub id: i64,
    pub title: String,
    pub artist_id: Option<i64>,
    pub artist: Option<String>,
    pub year: Option<i64>,
    pub cover_hash: Option<String>,
    pub track_count: i64,
}

impl Db {
    pub fn open(path: &Path) -> Result<Self> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let conn = Connection::open(path)?;
        Self::init(conn)
    }

    pub fn open_in_memory() -> Result<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> Result<Self> {
        conn.create_collation("NATSORT", crate::natural::natural_cmp)?;
        conn.execute_batch(
            "PRAGMA journal_mode=WAL;
             PRAGMA synchronous=NORMAL;
             PRAGMA foreign_keys=ON;
             PRAGMA busy_timeout=5000;
             PRAGMA temp_store=MEMORY;
             PRAGMA cache_size=-8000;", // 8 MB page cache cap
        )?;
        // Fast path: an up-to-date database needs no DDL and, above all, no
        // write. Opening must never wait on the write lock (the scanner may
        // hold it), or the UI thread freezes.
        if Self::is_current(&conn) {
            return Ok(Db { conn });
        }
        conn.execute_batch(SCHEMA)?;
        // v0.4 → v0.5: per-track art, genre, composer, "added" date. Old rows are
        // re-read on the next scan (mtime reset) so the new fields get filled.
        let has_genre: bool = conn
            .prepare("SELECT 1 FROM pragma_table_info('tracks') WHERE name='genre'")?
            .exists([])?;
        if !has_genre {
            conn.execute_batch(
                "ALTER TABLE tracks ADD COLUMN cover_hash TEXT;
                 ALTER TABLE tracks ADD COLUMN genre TEXT;
                 ALTER TABLE tracks ADD COLUMN composer TEXT;
                 ALTER TABLE tracks ADD COLUMN added_at INTEGER;
                 ALTER TABLE tracks ADD COLUMN format TEXT;
                 ALTER TABLE tracks ADD COLUMN sample_rate INTEGER;
                 ALTER TABLE tracks ADD COLUMN bit_depth INTEGER;
                 ALTER TABLE tracks ADD COLUMN bitrate INTEGER;
                 UPDATE tracks SET added_at = mtime;
                 UPDATE tracks SET mtime = 0 WHERE path NOT LIKE 'remote://%';",
            )?;
        }
        let has_smart: bool = conn
            .prepare("SELECT 1 FROM pragma_table_info('playlists') WHERE name='query'")?
            .exists([])?;
        if !has_smart {
            conn.execute_batch(
                "ALTER TABLE playlists ADD COLUMN query TEXT;
                 ALTER TABLE playlists ADD COLUMN sort TEXT;
                 ALTER TABLE playlists ADD COLUMN lim INTEGER;",
            )?;
        }
        // v0.7 → v0.8: explicit marking. Local files are re-read on the next
        // scan to pick up advisory tags; lyrics already cached are checked now.
        let has_explicit: bool = conn
            .prepare("SELECT 1 FROM pragma_table_info('tracks') WHERE name='explicit'")?
            .exists([])?;
        if !has_explicit {
            conn.execute_batch(
                "ALTER TABLE tracks ADD COLUMN explicit INTEGER;
                 ALTER TABLE tracks ADD COLUMN explicit_lyrics INTEGER;
                 ALTER TABLE tracks ADD COLUMN explicit_user INTEGER;
                 UPDATE tracks SET mtime = 0 WHERE path NOT LIKE 'remote://%';",
            )?;
            let rows: Vec<(i64, String)> = {
                let mut st = conn.prepare(
                    "SELECT track_id, COALESCE(synced, '') || char(10) || COALESCE(plain, '') FROM lyrics",
                )?;
                let it = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?;
                it.flatten().collect()
            };
            for (id, text) in rows {
                let e = crate::explicit::lyrics_are_explicit(&text) as i64;
                conn.execute("UPDATE tracks SET explicit_lyrics=?1 WHERE id=?2", params![e, id])?;
            }
        }
        conn.execute_batch(
            "CREATE INDEX IF NOT EXISTS tracks_genre ON tracks(genre COLLATE NOCASE);
             CREATE INDEX IF NOT EXISTS tracks_added ON tracks(added_at);",
        )?;
        conn.execute(
            "INSERT OR IGNORE INTO kv(k, v) VALUES ('schema_version', ?1)",
            [SCHEMA_VERSION.to_string()],
        )?;
        Ok(Db { conn })
    }

    fn is_current(conn: &Connection) -> bool {
        let q = |sql: &str| conn.prepare(sql).and_then(|mut st| st.exists([])).unwrap_or(false);
        q("SELECT 1 FROM kv WHERE k='schema_version'")
            && q("SELECT 1 FROM pragma_table_info('tracks') WHERE name='genre'")
            && q("SELECT 1 FROM pragma_table_info('playlists') WHERE name='query'")
            && q("SELECT 1 FROM pragma_table_info('tracks') WHERE name='explicit'")
            && q("SELECT 1 FROM sqlite_master WHERE type='index' AND name='tracks_added'")
            // 0.7.6: databases upgraded from older versions never got this table.
            && q("SELECT 1 FROM sqlite_master WHERE type='table' AND name='track_analysis'")
    }

    pub fn artist_id(&self, name: &str) -> Result<i64> {
        self.conn
            .execute("INSERT OR IGNORE INTO artists(name) VALUES (?1)", [name])?;
        Ok(self
            .conn
            .query_row("SELECT id FROM artists WHERE name = ?1", [name], |r| r.get(0))?)
    }

    pub fn album_id(
        &self,
        title: &str,
        artist_id: i64,
        year: Option<i64>,
        now: i64,
    ) -> Result<i64> {
        self.conn.execute(
            "INSERT OR IGNORE INTO albums(title, artist_id, year, added_at) VALUES (?1, ?2, ?3, ?4)",
            params![title, artist_id, year, now],
        )?;
        Ok(self.conn.query_row(
            "SELECT id FROM albums WHERE title = ?1 AND artist_id = ?2",
            params![title, artist_id],
            |r| r.get(0),
        )?)
    }

    /// Map of path -> (mtime, size) for every known track, used for incremental scans.
    pub fn known_files(&self) -> Result<std::collections::HashMap<String, (i64, i64)>> {
        let mut st = self.conn.prepare("SELECT path, mtime, size FROM tracks")?;
        let rows = st.query_map([], |r| Ok((r.get(0)?, (r.get(1)?, r.get(2)?))))?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    pub fn albums(&self) -> Result<Vec<AlbumRow>> {
        let mut st = self.conn.prepare_cached(
            "SELECT a.id, a.title, ar.name, a.year, a.cover_hash,
                    (SELECT COUNT(*) FROM tracks t WHERE t.album_id = a.id), a.artist_id
             FROM albums a LEFT JOIN artists ar ON ar.id = a.artist_id
             ORDER BY ar.name COLLATE NATSORT, a.year, a.title COLLATE NATSORT",
        )?;
        let rows = st.query_map([], |r| {
            Ok(AlbumRow {
                id: r.get(0)?,
                title: r.get(1)?,
                artist: r.get(2)?,
                year: r.get(3)?,
                cover_hash: r.get(4)?,
                track_count: r.get(5)?,
                artist_id: r.get(6)?,
            })
        })?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    pub fn album_tracks(&self, album_id: i64) -> Result<Vec<TrackRow>> {
        self.tracks_where("t.album_id = ?1 ORDER BY t.disc_no, t.track_no, t.title", [album_id])
    }

    pub fn track(&self, id: i64) -> Result<Option<TrackRow>> {
        Ok(self.tracks_where("t.id = ?1", [id])?.into_iter().next())
    }

    /// Full-text search; `query` is matched as prefix terms ("beat yel" finds "Yellow Submarine – The Beatles").
    pub fn search(&self, query: &str, limit: i64) -> Result<Vec<TrackRow>> {
        let fts: String = query
            .split_whitespace()
            .map(|w| format!("\"{}\"*", w.replace('"', "")))
            .collect::<Vec<_>>()
            .join(" ");
        if fts.is_empty() {
            return Ok(vec![]);
        }
        let mut st = self.conn.prepare_cached(
            &format!("SELECT {TRACK_COLS}
             FROM tracks_fts f JOIN tracks t ON t.id = f.rowid
             LEFT JOIN albums a ON a.id = t.album_id
             WHERE tracks_fts MATCH ?1 ORDER BY rank LIMIT ?2"),
        )?;
        let rows = st.query_map(params![fts, limit], map_track)?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    fn tracks_where<P: rusqlite::Params>(&self, clause: &str, p: P) -> Result<Vec<TrackRow>> {
        let sql = format!(
            "SELECT {TRACK_COLS}
             FROM tracks t LEFT JOIN albums a ON a.id = t.album_id WHERE {clause}"
        );
        let mut st = self.conn.prepare_cached(&sql)?;
        let rows = st.query_map(p, map_track)?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    // ---------- artists ----------

    /// Album artists (the ones that own at least one album), with a cover from one of their albums.
    pub fn artists(&self) -> Result<Vec<ArtistRow>> {
        let mut st = self.conn.prepare_cached(
            "SELECT ar.id, ar.name, COUNT(a.id),
                    (SELECT a2.cover_hash FROM albums a2 WHERE a2.artist_id = ar.id AND a2.cover_hash IS NOT NULL
                     ORDER BY a2.year DESC LIMIT 1)
             FROM artists ar JOIN albums a ON a.artist_id = ar.id
             GROUP BY ar.id ORDER BY ar.name COLLATE NATSORT",
        )?;
        let rows = st.query_map([], |r| {
            Ok(ArtistRow { id: r.get(0)?, name: r.get(1)?, album_count: r.get(2)?, cover_hash: r.get(3)? })
        })?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    /// Albums with at least one track whose path starts with `prefix` (e.g. one remote server).
    pub fn albums_with_path_prefix(&self, prefix: &str) -> Result<Vec<AlbumRow>> {
        let ids: std::collections::HashSet<i64> = {
            let mut st = self.conn.prepare(
                "SELECT DISTINCT album_id FROM tracks WHERE album_id IS NOT NULL AND substr(path, 1, length(?1)) = ?1",
            )?;
            let rows = st.query_map([prefix], |r| r.get(0))?;
            rows.flatten().collect()
        };
        Ok(self.albums()?.into_iter().filter(|a| ids.contains(&a.id)).collect())
    }

    pub fn artist_albums(&self, artist_id: i64) -> Result<Vec<AlbumRow>> {
        Ok(self.albums()?.into_iter().filter(|a| a.artist_id == Some(artist_id)).collect())
    }

    // ---------- favourites & history ----------

    pub fn set_starred(&self, track_id: i64, starred: bool) -> Result<()> {
        self.conn.execute("UPDATE tracks SET starred=?1 WHERE id=?2", params![starred as i64, track_id])?;
        Ok(())
    }

    /// The user's own explicit marking: Some(true/false) overrides tag and
    /// lyrics, None goes back to automatic.
    pub fn set_explicit_user(&self, track_id: i64, explicit: Option<bool>) -> Result<()> {
        self.conn.execute(
            "UPDATE tracks SET explicit_user=?1 WHERE id=?2",
            params![explicit.map(|b| b as i64), track_id],
        )?;
        Ok(())
    }

    pub fn all_tracks(&self) -> Result<Vec<TrackRow>> {
        self.tracks_where(
            "1 ORDER BY t.artist COLLATE NATSORT, a.year, a.title COLLATE NATSORT, t.disc_no, t.track_no",
            [],
        )
    }

    pub fn starred_tracks(&self) -> Result<Vec<TrackRow>> {
        self.tracks_where("t.starred = 1 ORDER BY t.artist COLLATE NATSORT, a.title COLLATE NATSORT, t.disc_no, t.track_no", [])
    }

    pub fn record_play(&self, track_id: i64, now: i64) -> Result<()> {
        self.conn.execute(
            "UPDATE tracks SET play_count = play_count + 1, last_played = ?1 WHERE id = ?2",
            params![now, track_id],
        )?;
        Ok(())
    }

    pub fn recent_tracks(&self, limit: i64) -> Result<Vec<TrackRow>> {
        self.tracks_where("t.last_played IS NOT NULL ORDER BY t.last_played DESC LIMIT ?1", [limit])
    }

    pub fn most_played(&self, limit: i64) -> Result<Vec<TrackRow>> {
        self.tracks_where("t.play_count > 0 ORDER BY t.play_count DESC, t.last_played DESC LIMIT ?1", [limit])
    }

    /// Tracks by id, in the order given (used to restore the play queue).
    pub fn tracks_by_ids(&self, ids: &[i64]) -> Result<Vec<TrackRow>> {
        let mut out = Vec::with_capacity(ids.len());
        for id in ids {
            if let Some(t) = self.track(*id)? {
                out.push(t);
            }
        }
        Ok(out)
    }

    // ---------- playlists ----------

    pub fn playlists(&self) -> Result<Vec<PlaylistRow>> {
        let mut st = self.conn.prepare_cached(
            "SELECT p.id, p.name, COUNT(i.track_id),
                    (SELECT a.cover_hash FROM playlist_items i2 JOIN tracks t ON t.id = i2.track_id
                     JOIN albums a ON a.id = t.album_id WHERE i2.playlist_id = p.id AND a.cover_hash IS NOT NULL
                     ORDER BY i2.pos LIMIT 1), p.query, p.sort, p.lim
             FROM playlists p LEFT JOIN playlist_items i ON i.playlist_id = p.id
             GROUP BY p.id ORDER BY p.name COLLATE NATSORT",
        )?;
        let rows = st.query_map([], |r| {
            Ok(PlaylistRow {
                id: r.get(0)?,
                name: r.get(1)?,
                track_count: r.get(2)?,
                cover_hash: r.get(3)?,
                smart: r.get::<_, Option<String>>(4)?.map(|q| (q, r.get(5).unwrap_or_default(), r.get(6).unwrap_or(0))),
            })
        })?;
        let mut out: Vec<PlaylistRow> = rows.collect::<std::result::Result<_, _>>()?;
        // Smart playlists: count and cover come from the saved search.
        for p in out.iter_mut() {
            if let Some((q, sort, lim)) = &p.smart {
                let t = self.query_tracks(q, sort, *lim)?;
                p.track_count = t.len() as i64;
                p.cover_hash = t.iter().find_map(|t| t.cover_hash.clone());
            }
        }
        Ok(out)
    }

    /// Create or update a smart playlist (a saved search with a sort order and an optional limit).
    pub fn save_smart_playlist(&self, id: Option<i64>, name: &str, query: &str, sort: &str, limit: i64) -> Result<i64> {
        match id {
            Some(id) => {
                self.conn.execute(
                    "UPDATE playlists SET name=?1, query=?2, sort=?3, lim=?4 WHERE id=?5",
                    params![name, query, sort, limit, id],
                )?;
                Ok(id)
            }
            None => {
                self.conn.execute(
                    "INSERT INTO playlists(name, query, sort, lim) VALUES (?1,?2,?3,?4)",
                    params![name, query, sort, limit],
                )?;
                Ok(self.conn.last_insert_rowid())
            }
        }
    }

    pub fn create_playlist(&self, name: &str) -> Result<i64> {
        self.conn.execute("INSERT INTO playlists(name) VALUES (?1)", [name])?;
        Ok(self.conn.last_insert_rowid())
    }

    pub fn rename_playlist(&self, id: i64, name: &str) -> Result<()> {
        self.conn.execute("UPDATE playlists SET name=?1 WHERE id=?2", params![name, id])?;
        Ok(())
    }

    pub fn delete_playlist(&self, id: i64) -> Result<()> {
        self.conn.execute("DELETE FROM playlists WHERE id=?1", [id])?;
        Ok(())
    }

    pub fn add_to_playlist(&self, playlist_id: i64, track_ids: &[i64]) -> Result<()> {
        let next: i64 = self.conn.query_row(
            "SELECT COALESCE(MAX(pos) + 1, 0) FROM playlist_items WHERE playlist_id=?1",
            [playlist_id],
            |r| r.get(0),
        )?;
        let mut st = self
            .conn
            .prepare_cached("INSERT INTO playlist_items(playlist_id, pos, track_id) VALUES (?1, ?2, ?3)")?;
        for (i, t) in track_ids.iter().enumerate() {
            st.execute(params![playlist_id, next + i as i64, t])?;
        }
        Ok(())
    }

    /// Remove the item at `pos` and close the gap so positions stay contiguous.
    pub fn remove_from_playlist(&self, playlist_id: i64, pos: i64) -> Result<()> {
        self.conn.execute("DELETE FROM playlist_items WHERE playlist_id=?1 AND pos=?2", params![playlist_id, pos])?;
        // Two-step shift avoids transient PRIMARY KEY collisions.
        self.conn.execute(
            "UPDATE playlist_items SET pos = -(pos - 1) - 1 WHERE playlist_id=?1 AND pos > ?2",
            params![playlist_id, pos],
        )?;
        self.conn.execute(
            "UPDATE playlist_items SET pos = -pos - 1 WHERE playlist_id=?1 AND pos < 0",
            params![playlist_id],
        )?;
        Ok(())
    }

    /// Move the item at `from` to `to` (both 0-based), shifting the others.
    pub fn move_in_playlist(&self, playlist_id: i64, from: i64, to: i64) -> Result<()> {
        let mut ids: Vec<i64> = {
            let mut st = self.conn.prepare_cached("SELECT track_id FROM playlist_items WHERE playlist_id=?1 ORDER BY pos")?;
            let rows = st.query_map([playlist_id], |r| r.get(0))?;
            rows.collect::<std::result::Result<_, _>>()?
        };
        let (f, t) = (from as usize, to as usize);
        if f >= ids.len() || t >= ids.len() || f == t {
            return Ok(());
        }
        let id = ids.remove(f);
        ids.insert(t, id);
        let tx = self.conn.unchecked_transaction()?;
        tx.execute("DELETE FROM playlist_items WHERE playlist_id=?1", [playlist_id])?;
        {
            let mut st = tx.prepare_cached("INSERT INTO playlist_items(playlist_id, pos, track_id) VALUES (?1, ?2, ?3)")?;
            for (i, t) in ids.iter().enumerate() {
                st.execute(params![playlist_id, i as i64, t])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    pub fn playlist_tracks(&self, playlist_id: i64) -> Result<Vec<TrackRow>> {
        let smart: Option<(Option<String>, Option<String>, Option<i64>)> = self
            .conn
            .query_row("SELECT query, sort, lim FROM playlists WHERE id=?1", [playlist_id], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
            .optional()?;
        if let Some((Some(q), sort, lim)) = smart {
            return self.query_tracks(&q, sort.as_deref().unwrap_or(""), lim.unwrap_or(0));
        }
        let mut st = self.conn.prepare_cached(&format!(
            "SELECT {TRACK_COLS} FROM playlist_items i JOIN tracks t ON t.id = i.track_id
             LEFT JOIN albums a ON a.id = t.album_id WHERE i.playlist_id = ?1 ORDER BY i.pos"
        ))?;
        let rows = st.query_map([playlist_id], map_track)?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    // ---------- key/value settings ----------

    pub fn get_kv(&self, k: &str) -> Result<Option<String>> {
        Ok(self.conn.query_row("SELECT v FROM kv WHERE k=?1", [k], |r| r.get(0)).optional()?)
    }

    pub fn set_kv(&self, k: &str, v: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO kv(k,v) VALUES(?1,?2) ON CONFLICT(k) DO UPDATE SET v=excluded.v",
            params![k, v],
        )?;
        Ok(())
    }

    pub fn counts(&self) -> Result<(i64, i64, i64)> {
        Ok(self.conn.query_row(
            "SELECT (SELECT COUNT(*) FROM tracks), (SELECT COUNT(*) FROM albums), (SELECT COUNT(*) FROM artists)",
            [],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )?)
    }

    pub fn cached_lyrics(&self, track_id: i64) -> Result<Option<(String, Option<String>, Option<String>)>> {
        Ok(self
            .conn
            .query_row(
                "SELECT source, synced, plain FROM lyrics WHERE track_id = ?1",
                [track_id],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()?)
    }

    pub fn store_lyrics(
        &self,
        track_id: i64,
        source: &str,
        synced: Option<&str>,
        plain: Option<&str>,
        now: i64,
    ) -> Result<()> {
        self.conn.execute(
            "INSERT INTO lyrics(track_id, source, synced, plain, fetched_at) VALUES (?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(track_id) DO UPDATE SET source=excluded.source, synced=excluded.synced,
                 plain=excluded.plain, fetched_at=excluded.fetched_at",
            params![track_id, source, synced, plain, now],
        )?;
        let text = format!("{}\n{}", synced.unwrap_or_default(), plain.unwrap_or_default());
        let e = crate::explicit::lyrics_are_explicit(&text) as i64;
        self.conn.execute("UPDATE tracks SET explicit_lyrics=?1 WHERE id=?2", params![e, track_id])?;
        Ok(())
    }
}

pub(crate) fn map_track(r: &rusqlite::Row) -> rusqlite::Result<TrackRow> {
    Ok(TrackRow {
        id: r.get(0)?,
        path: r.get(1)?,
        title: r.get(2)?,
        artist: r.get(3)?,
        album: r.get(4)?,
        album_id: r.get(5)?,
        duration_ms: r.get(6)?,
        starred: r.get::<_, i64>(7)? != 0,
        cover_hash: r.get(8)?,
        track_gain: r.get(9)?,
        album_gain: r.get(10)?,
        year: r.get(11)?,
        genre: r.get(12)?,
        album_artist: r.get(13)?,
        format: r.get(14)?,
        sample_rate: r.get(15)?,
        bit_depth: r.get(16)?,
        bitrate: r.get(17)?,
        explicit: r.get(18)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn old_database_gets_analysis_table() {
        let dir = std::env::temp_dir().join(format!("arara-mig-{}", std::process::id()));
        let path = dir.join("db.sqlite");
        let db = Db::open(&path).unwrap();
        db.conn.execute_batch("DROP TABLE track_analysis").unwrap();
        drop(db);
        let db = Db::open(&path).unwrap();
        let ok = db
            .conn
            .prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='track_analysis'")
            .unwrap()
            .exists([])
            .unwrap();
        assert!(ok);
        let _ = std::fs::remove_dir_all(dir);
    }

    fn db_with_tracks(n: i64) -> Db {
        let db = Db::open_in_memory().unwrap();
        let ar = db.artist_id("Arara").unwrap();
        let al = db.album_id("Voo", ar, Some(2024), 0).unwrap();
        for i in 0..n {
            db.conn
                .execute(
                    "INSERT INTO tracks(path, mtime, size, title, artist, album_id, track_no) VALUES (?1,0,0,?2,'Arara',?3,?4)",
                    params![format!("/m/{i}.mp3"), format!("Faixa {i}"), al, i],
                )
                .unwrap();
        }
        db
    }

    #[test]
    fn playlists_keep_order_after_removal() {
        let db = db_with_tracks(4);
        let p = db.create_playlist("Favoritas da semana").unwrap();
        db.add_to_playlist(p, &[1, 2, 3, 4]).unwrap();
        db.remove_from_playlist(p, 1).unwrap();
        let ids: Vec<i64> = db.playlist_tracks(p).unwrap().iter().map(|t| t.id).collect();
        assert_eq!(ids, vec![1, 3, 4]);
        db.add_to_playlist(p, &[2]).unwrap();
        let ids: Vec<i64> = db.playlist_tracks(p).unwrap().iter().map(|t| t.id).collect();
        assert_eq!(ids, vec![1, 3, 4, 2]);
        db.move_in_playlist(p, 3, 0).unwrap();
        db.move_in_playlist(p, 1, 2).unwrap();
        let ids: Vec<i64> = db.playlist_tracks(p).unwrap().iter().map(|t| t.id).collect();
        assert_eq!(ids, vec![2, 3, 1, 4]);
        assert_eq!(db.playlists().unwrap()[0].track_count, 4);
        db.delete_playlist(p).unwrap();
        assert!(db.playlists().unwrap().is_empty());
    }

    #[test]
    fn stars_history_artists() {
        let db = db_with_tracks(3);
        db.set_starred(2, true).unwrap();
        assert_eq!(db.starred_tracks().unwrap().len(), 1);
        assert!(db.track(2).unwrap().unwrap().starred);
        db.record_play(3, 100).unwrap();
        db.record_play(1, 200).unwrap();
        db.record_play(3, 300).unwrap();
        let recent: Vec<i64> = db.recent_tracks(10).unwrap().iter().map(|t| t.id).collect();
        assert_eq!(recent, vec![3, 1]);
        assert_eq!(db.most_played(1).unwrap()[0].id, 3);
        let a = db.artists().unwrap();
        assert_eq!(a.len(), 1);
        assert_eq!(db.artist_albums(a[0].id).unwrap().len(), 1);
    }
}
