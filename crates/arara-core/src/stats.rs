//! Listening history and the yearly/monthly recap ("Retrospectiva"), like
//! Spotify Wrapped, Apple Music Replay and YouTube Music Recap.
//!
//! Every time a song starts, a row goes into `listens` with a snapshot of the
//! track (title, artist, album, genre, cover), so the recap survives files
//! being moved or deleted. While the song plays, the UI adds the time actually
//! heard (pauses and seeks don't count). A listen of 30 s or more counts as a
//! "play", the same rule Spotify uses; minutes always count.
//!
//! Everything stays on this computer.

use rusqlite::{params, OptionalExtension};
use serde::Serialize;
use std::collections::HashMap;

use crate::db::Db;
use crate::Result;

/// A listen shorter than this is a skip: its minutes count, but not as a play.
pub const PLAY_MIN_MS: i64 = 30_000;

const STATS_SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS listens (
    id         INTEGER PRIMARY KEY,
    track_id   INTEGER REFERENCES tracks(id) ON DELETE SET NULL,
    title      TEXT NOT NULL,
    artist     TEXT NOT NULL,
    album      TEXT,
    album_id   INTEGER,
    genre      TEXT,
    cover_hash TEXT,
    started_at INTEGER NOT NULL,   -- unix seconds
    ms         INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS listens_time ON listens(started_at);
"#;

#[derive(Debug, Default, Serialize, Clone)]
pub struct Ranked {
    pub name: String,
    /// Artist of a song or album; empty for artists and genres.
    pub artist: String,
    pub ms: i64,
    pub plays: i64,
    pub cover_hash: Option<String>,
    /// track id (songs), album id (albums), artist id (artists), when known.
    pub id: Option<i64>,
}

#[derive(Debug, Default, Serialize)]
pub struct Recap {
    pub total_ms: i64,
    pub plays: i64,
    pub tracks: i64,
    pub artists: i64,
    pub albums: i64,
    pub days_active: i64,
    pub longest_streak: i64,
    pub top_artists: Vec<Ranked>,
    pub top_tracks: Vec<Ranked>,
    pub top_albums: Vec<Ranked>,
    pub top_genres: Vec<Ranked>,
    /// Artists first heard in this period, most listened first.
    pub new_artists: Vec<Ranked>,
    /// Milliseconds per local hour of day (0..24) and weekday (0 = Sunday).
    pub hours: Vec<i64>,
    pub weekdays: Vec<i64>,
    /// (local date "YYYY-MM-DD", ms), in order.
    pub days: Vec<(String, i64)>,
    pub first_listen: Option<i64>,
}

/// "A feat. B" / "A ft. B" / "A; B" → ["A", "B"]. Commas and "&" are left
/// alone on purpose: "Earth, Wind & Fire", "Chitãozinho & Xororó".
pub fn split_artists(s: &str) -> Vec<String> {
    let mut parts = vec![s.to_string()];
    for sep in [" feat. ", " feat ", " ft. ", " featuring ", " Feat. ", " Ft. ", " FEAT. ", "; "] {
        parts = parts.iter().flat_map(|p| p.split(sep).map(str::to_string).collect::<Vec<_>>()).collect();
    }
    let mut out: Vec<String> = Vec::new();
    for p in parts {
        let p = p.trim().trim_matches(|c| c == '(' || c == ')').trim().to_string();
        if !p.is_empty() && !out.iter().any(|o| o.eq_ignore_ascii_case(&p)) {
            out.push(p);
        }
    }
    if out.is_empty() {
        out.push("Artista desconhecido".into());
    }
    out
}

impl Db {
    /// Creates the history table when missing. Reads only when it exists, so it
    /// never waits on the scanner's write lock in the common case.
    pub fn ensure_stats(&self) -> Result<()> {
        let exists = self
            .conn
            .prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='listens'")?
            .exists([])?;
        if !exists {
            self.conn.execute_batch(STATS_SCHEMA)?;
        }
        Ok(())
    }

    /// A song started: snapshot it and return the listen id (0 if the track is unknown).
    pub fn begin_listen(&self, track_id: i64, now: i64) -> Result<i64> {
        self.ensure_stats()?;
        let n = self.conn.execute(
            "INSERT INTO listens(track_id, title, artist, album, album_id, genre, cover_hash, started_at)
             SELECT t.id, t.title, t.artist, a.title, t.album_id, t.genre, COALESCE(t.cover_hash, a.cover_hash), ?2
             FROM tracks t LEFT JOIN albums a ON a.id = t.album_id WHERE t.id = ?1",
            params![track_id, now],
        )?;
        Ok(if n == 1 { self.conn.last_insert_rowid() } else { 0 })
    }

    /// Adds time actually heard to a listen.
    pub fn add_listen_ms(&self, listen_id: i64, ms: i64) -> Result<()> {
        if listen_id <= 0 || ms <= 0 {
            return Ok(());
        }
        // A single tick can't be longer than a couple of minutes (guards against clock jumps).
        self.conn.execute(
            "UPDATE listens SET ms = ms + ?1 WHERE id = ?2",
            params![ms.min(180_000), listen_id],
        )?;
        Ok(())
    }

    /// Drops the whole listening history.
    pub fn clear_listens(&self) -> Result<()> {
        self.ensure_stats()?;
        self.conn.execute("DELETE FROM listens", [])?;
        Ok(())
    }

    /// Unix time of the first listen ever, if any.
    pub fn first_listen(&self) -> Result<Option<i64>> {
        self.ensure_stats()?;
        Ok(self
            .conn
            .query_row("SELECT MIN(started_at) FROM listens WHERE ms > 0", [], |r| r.get::<_, Option<i64>>(0))
            .optional()?
            .flatten())
    }

    /// Total time heard in [from, to).
    pub fn listened_ms(&self, from: i64, to: i64) -> Result<i64> {
        self.ensure_stats()?;
        Ok(self.conn.query_row(
            "SELECT COALESCE(SUM(ms), 0) FROM listens WHERE started_at >= ?1 AND started_at < ?2",
            params![from, to],
            |r| r.get(0),
        )?)
    }

    /// The recap for [from, to) (unix seconds; use 0 and i64::MAX for "all time").
    pub fn recap(&self, from: i64, to: i64, top: usize) -> Result<Recap> {
        self.ensure_stats()?;
        struct Row {
            track_id: Option<i64>,
            title: String,
            artist: String,
            album: Option<String>,
            album_id: Option<i64>,
            genre: Option<String>,
            cover: Option<String>,
            started: i64,
            ms: i64,
            day: String,
            hour: usize,
            wday: usize,
        }
        let rows: Vec<Row> = {
            let mut st = self.conn.prepare(
                "SELECT track_id, title, artist, album, album_id, genre, cover_hash, started_at, ms,
                        date(started_at, 'unixepoch', 'localtime'),
                        CAST(strftime('%H', started_at, 'unixepoch', 'localtime') AS INTEGER),
                        CAST(strftime('%w', started_at, 'unixepoch', 'localtime') AS INTEGER)
                 FROM listens WHERE ms > 0 AND started_at >= ?1 AND started_at < ?2 ORDER BY started_at",
            )?;
            let it = st.query_map(params![from, to], |r| {
                Ok(Row {
                    track_id: r.get(0)?,
                    title: r.get(1)?,
                    artist: r.get(2)?,
                    album: r.get(3)?,
                    album_id: r.get(4)?,
                    genre: r.get(5)?,
                    cover: r.get(6)?,
                    started: r.get(7)?,
                    ms: r.get(8)?,
                    day: r.get(9)?,
                    hour: r.get::<_, i64>(10)?.clamp(0, 23) as usize,
                    wday: r.get::<_, i64>(11)?.clamp(0, 6) as usize,
                })
            })?;
            it.collect::<std::result::Result<_, _>>()?
        };

        let mut rc = Recap { hours: vec![0; 24], weekdays: vec![0; 7], ..Default::default() };
        rc.first_listen = rows.first().map(|r| r.started);
        let mut artists: HashMap<String, Ranked> = HashMap::new();
        let mut tracks: HashMap<String, Ranked> = HashMap::new();
        let mut albums: HashMap<String, Ranked> = HashMap::new();
        let mut genres: HashMap<String, Ranked> = HashMap::new();
        let mut days: Vec<(String, i64)> = Vec::new();

        fn bump(map: &mut HashMap<String, Ranked>, key: String, make: impl FnOnce() -> Ranked, ms: i64, play: bool) {
            let e = map.entry(key).or_insert_with(make);
            e.ms += ms;
            e.plays += play as i64;
        }

        for r in &rows {
            let play = r.ms >= PLAY_MIN_MS;
            rc.total_ms += r.ms;
            rc.plays += play as i64;
            rc.hours[r.hour] += r.ms;
            rc.weekdays[r.wday] += r.ms;
            match days.last_mut() {
                Some((d, ms)) if *d == r.day => *ms += r.ms,
                _ => days.push((r.day.clone(), r.ms)),
            }
            for a in split_artists(&r.artist) {
                let cover = r.cover.clone();
                bump(&mut artists, a.to_lowercase(), || Ranked { name: a.clone(), cover_hash: cover, ..Default::default() }, r.ms, play);
            }
            let tkey = match r.track_id {
                Some(id) => format!("#{id}"),
                None => format!("{}\u{1}{}", r.title.to_lowercase(), r.artist.to_lowercase()),
            };
            bump(
                &mut tracks,
                tkey,
                || Ranked { name: r.title.clone(), artist: r.artist.clone(), cover_hash: r.cover.clone(), id: r.track_id, ..Default::default() },
                r.ms,
                play,
            );
            if let Some(al) = r.album.as_ref().filter(|s| !s.is_empty()) {
                let key = match r.album_id {
                    Some(id) => format!("#{id}"),
                    None => al.to_lowercase(),
                };
                bump(
                    &mut albums,
                    key,
                    || Ranked { name: al.clone(), artist: r.artist.clone(), cover_hash: r.cover.clone(), id: r.album_id, ..Default::default() },
                    r.ms,
                    play,
                );
            }
            if let Some(g) = r.genre.as_ref().map(|g| g.trim()).filter(|g| !g.is_empty()) {
                bump(&mut genres, g.to_lowercase(), || Ranked { name: g.to_string(), ..Default::default() }, r.ms, play);
            }
        }

        rc.tracks = tracks.len() as i64;
        rc.artists = artists.len() as i64;
        rc.albums = albums.len() as i64;
        rc.days_active = days.len() as i64;
        rc.longest_streak = longest_streak(&days);

        // Artists heard for the first time in this period.
        let seen_before: std::collections::HashSet<String> = if from > 0 {
            let mut st = self.conn.prepare("SELECT DISTINCT artist FROM listens WHERE ms > 0 AND started_at < ?1")?;
            let it = st.query_map([from], |r| r.get::<_, String>(0))?;
            it.flatten().flat_map(|a| split_artists(&a)).map(|a| a.to_lowercase()).collect()
        } else {
            Default::default()
        };

        let rank = |m: HashMap<String, Ranked>| {
            let mut v: Vec<Ranked> = m.into_values().collect();
            v.sort_by(|a, b| b.ms.cmp(&a.ms).then(b.plays.cmp(&a.plays)).then(a.name.cmp(&b.name)));
            v
        };
        let all_artists = rank(artists);
        if from > 0 {
            rc.new_artists = all_artists
                .iter()
                .filter(|a| !seen_before.contains(&a.name.to_lowercase()))
                .take(top)
                .cloned()
                .collect();
        }
        rc.top_artists = all_artists.into_iter().take(top).collect();
        rc.top_tracks = rank(tracks).into_iter().take(top).collect();
        rc.top_albums = rank(albums).into_iter().take(top).collect();
        rc.top_genres = rank(genres).into_iter().take(top).collect();
        rc.days = days;

        // Artist pages and a proper artist picture (an album cover of theirs) when in the library.
        for a in rc.top_artists.iter_mut().chain(rc.new_artists.iter_mut()) {
            let found: Option<(i64, Option<String>)> = self
                .conn
                .query_row(
                    "SELECT ar.id, (SELECT a2.cover_hash FROM albums a2 WHERE a2.artist_id = ar.id AND a2.cover_hash IS NOT NULL
                                    ORDER BY a2.year DESC LIMIT 1)
                     FROM artists ar WHERE ar.name = ?1",
                    [&a.name],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )
                .optional()?;
            if let Some((id, cover)) = found {
                a.id = Some(id);
                if cover.is_some() {
                    a.cover_hash = cover;
                }
            }
        }
        Ok(rc)
    }
}

/// Longest run of consecutive local dates ("YYYY-MM-DD", sorted).
fn longest_streak(days: &[(String, i64)]) -> i64 {
    fn ordinal(d: &str) -> Option<i64> {
        let mut it = d.split('-').map(|p| p.parse::<i64>().ok());
        let (y, m, dd) = (it.next()??, it.next()??, it.next()??);
        // Days since the civil epoch (Howard Hinnant's algorithm).
        let y = if m <= 2 { y - 1 } else { y };
        let era = y.div_euclid(400);
        let yoe = y - era * 400;
        let mp = (m + 9) % 12;
        let doy = (153 * mp + 2) / 5 + dd - 1;
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        Some(era * 146_097 + doe)
    }
    let mut best = 0;
    let mut run = 0;
    let mut prev: Option<i64> = None;
    for (d, _) in days {
        let Some(o) = ordinal(d) else { continue };
        run = if prev == Some(o - 1) { run + 1 } else { 1 };
        best = best.max(run);
        prev = Some(o);
    }
    best
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::NewTrack;

    fn track<'a>(path: &'a str, title: &'a str, artist: &'a str, album: &'a str, genre: &'a str) -> NewTrack<'a> {
        NewTrack {
            path,
            mtime: 1,
            size: 1,
            title,
            artist,
            album_artist: artist,
            album: Some(album),
            track_no: Some(1),
            disc_no: None,
            year: Some(2020),
            duration_ms: 200_000,
            track_gain: None,
            album_gain: None,
            cover_hash: None,
            genre: Some(genre),
            composer: None,
            format: None,
            sample_rate: None,
            bit_depth: None,
            bitrate: None,
            explicit: None, art_hash: None, folder_art: None,
        }
    }

    #[test]
    fn splits_featured_artists_only() {
        assert_eq!(split_artists("Anitta feat. J Balvin"), vec!["Anitta", "J Balvin"]);
        assert_eq!(split_artists("Earth, Wind & Fire"), vec!["Earth, Wind & Fire"]);
        assert_eq!(split_artists("A; B"), vec!["A", "B"]);
        assert_eq!(split_artists(""), vec!["Artista desconhecido"]);
    }

    #[test]
    fn recap_ranks_by_time_heard() {
        let db = Db::open_in_memory().unwrap();
        db.conn.execute_batch("BEGIN").unwrap();
        crate::db::upsert_track(&db.conn, &track("/a", "Song A", "Alpha", "Album A", "Rock"), 0).unwrap();
        crate::db::upsert_track(&db.conn, &track("/b", "Song B", "Beta feat. Alpha", "Album B", "Pop"), 0).unwrap();
        db.conn.execute_batch("COMMIT").unwrap();
        let id = |p: &str| db.conn.query_row("SELECT id FROM tracks WHERE path=?1", [p], |r| r.get::<_, i64>(0)).unwrap();
        let (a, b) = (id("/a"), id("/b"));

        let day = 86_400;
        let base = 1_700_000_000;
        // Alpha alone: 3 full plays over three days in a row; Beta: one long play and one skip.
        for i in 0..3 {
            let l = db.begin_listen(a, base + i * day).unwrap();
            db.add_listen_ms(l, 120_000).unwrap();
        }
        let l = db.begin_listen(b, base + 10 * day).unwrap();
        db.add_listen_ms(l, 150_000).unwrap();
        let l = db.begin_listen(b, base + 10 * day + 100).unwrap();
        db.add_listen_ms(l, 5_000).unwrap();
        // Outside the period.
        let l = db.begin_listen(b, base - 30 * day).unwrap();
        db.add_listen_ms(l, 100_000).unwrap();

        let r = db.recap(base, base + 20 * day, 5).unwrap();
        assert_eq!(r.total_ms, 360_000 + 155_000);
        assert_eq!(r.plays, 4);
        assert_eq!(r.top_tracks[0].name, "Song A");
        assert_eq!(r.top_tracks[0].plays, 3);
        // Alpha gets credit for the featured song too.
        assert_eq!(r.top_artists[0].name, "Alpha");
        assert_eq!(r.top_artists[0].ms, 360_000 + 155_000);
        assert_eq!(r.top_artists[1].name, "Beta");
        assert!(r.top_artists[0].id.is_some());
        assert_eq!(r.top_genres[0].name, "Rock");
        assert!(r.longest_streak >= 3);
        // Beta and Alpha were both heard before the period (the old listen of Song B).
        assert!(r.new_artists.is_empty());
        assert_eq!(db.listened_ms(0, i64::MAX).unwrap(), 360_000 + 155_000 + 100_000);

        // History survives the file disappearing.
        db.conn.execute("DELETE FROM tracks WHERE id=?1", [a]).unwrap();
        let r = db.recap(base, base + 20 * day, 5).unwrap();
        assert_eq!(r.top_tracks[0].name, "Song A");
        assert_eq!(r.top_tracks[0].id, None);

        db.clear_listens().unwrap();
        assert_eq!(db.recap(0, i64::MAX, 5).unwrap().total_ms, 0);
    }
}
