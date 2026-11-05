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
    last_played INTEGER
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
    id   INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS playlist_items (
    playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    pos         INTEGER NOT NULL,
    track_id    INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    PRIMARY KEY (playlist_id, pos)
);
CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT);
"#;

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
}

#[derive(Debug, Clone)]
pub struct AlbumRow {
    pub id: i64,
    pub title: String,
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
        conn.execute_batch(
            "PRAGMA journal_mode=WAL;
             PRAGMA synchronous=NORMAL;
             PRAGMA foreign_keys=ON;
             PRAGMA busy_timeout=5000;
             PRAGMA temp_store=MEMORY;
             PRAGMA cache_size=-8000;", // 8 MB page cache cap
        )?;
        conn.execute_batch(SCHEMA)?;
        conn.execute(
            "INSERT OR IGNORE INTO kv(k, v) VALUES ('schema_version', ?1)",
            [SCHEMA_VERSION.to_string()],
        )?;
        Ok(Db { conn })
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
                    (SELECT COUNT(*) FROM tracks t WHERE t.album_id = a.id)
             FROM albums a LEFT JOIN artists ar ON ar.id = a.artist_id
             ORDER BY ar.name, a.year, a.title",
        )?;
        let rows = st.query_map([], |r| {
            Ok(AlbumRow {
                id: r.get(0)?,
                title: r.get(1)?,
                artist: r.get(2)?,
                year: r.get(3)?,
                cover_hash: r.get(4)?,
                track_count: r.get(5)?,
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
            "SELECT t.id, t.path, t.title, t.artist, a.title, t.album_id, t.duration_ms
             FROM tracks_fts f JOIN tracks t ON t.id = f.rowid
             LEFT JOIN albums a ON a.id = t.album_id
             WHERE tracks_fts MATCH ?1 ORDER BY rank LIMIT ?2",
        )?;
        let rows = st.query_map(params![fts, limit], map_track)?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
    }

    fn tracks_where<P: rusqlite::Params>(&self, clause: &str, p: P) -> Result<Vec<TrackRow>> {
        let sql = format!(
            "SELECT t.id, t.path, t.title, t.artist, a.title, t.album_id, t.duration_ms
             FROM tracks t LEFT JOIN albums a ON a.id = t.album_id WHERE {clause}"
        );
        let mut st = self.conn.prepare_cached(&sql)?;
        let rows = st.query_map(p, map_track)?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
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
        Ok(())
    }
}

fn map_track(r: &rusqlite::Row) -> rusqlite::Result<TrackRow> {
    Ok(TrackRow {
        id: r.get(0)?,
        path: r.get(1)?,
        title: r.get(2)?,
        artist: r.get(3)?,
        album: r.get(4)?,
        album_id: r.get(5)?,
        duration_ms: r.get(6)?,
    })
}
