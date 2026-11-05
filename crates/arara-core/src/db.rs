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
    pub starred: bool,
    pub cover_hash: Option<String>,
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
}

const TRACK_COLS: &str =
    "t.id, t.path, t.title, t.artist, a.title, t.album_id, t.duration_ms, t.starred, a.cover_hash";

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

    pub fn artist_albums(&self, artist_id: i64) -> Result<Vec<AlbumRow>> {
        Ok(self.albums()?.into_iter().filter(|a| a.artist_id == Some(artist_id)).collect())
    }

    // ---------- favourites & history ----------

    pub fn set_starred(&self, track_id: i64, starred: bool) -> Result<()> {
        self.conn.execute("UPDATE tracks SET starred=?1 WHERE id=?2", params![starred as i64, track_id])?;
        Ok(())
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
                     ORDER BY i2.pos LIMIT 1)
             FROM playlists p LEFT JOIN playlist_items i ON i.playlist_id = p.id
             GROUP BY p.id ORDER BY p.name COLLATE NATSORT",
        )?;
        let rows = st.query_map([], |r| {
            Ok(PlaylistRow { id: r.get(0)?, name: r.get(1)?, track_count: r.get(2)?, cover_hash: r.get(3)? })
        })?;
        Ok(rows.collect::<std::result::Result<_, _>>()?)
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

    pub fn playlist_tracks(&self, playlist_id: i64) -> Result<Vec<TrackRow>> {
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
        starred: r.get::<_, i64>(7)? != 0,
        cover_hash: r.get(8)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

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
